# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReceiptParser::Steps::ClassifyRows do
  def classify(*texts)
    described_class.new.call(context(rows: rows(*texts)))
  end

  def kinds(*texts)
    classify(*texts).classified.map { [ it.text, it.kind ] }
  end

  it "classifies a simple receipt" do
    expect(kinds(
      "LOBLAWS #1234",
      "BANANAS 0.97",
      "PC MILK 2% 4L 6.49",
      "SUBTOTAL 7.46",
      "HST 13% 0.97",
      "TOTAL 8.43",
      "VISA 8.43",
      "THANK YOU"
    )).to eq([
      [ "LOBLAWS #1234", :other ],
      [ "BANANAS 0.97", :item ],
      [ "PC MILK 2% 4L 6.49", :item ],
      [ "SUBTOTAL 7.46", :subtotal ],
      [ "HST 13% 0.97", :tax ],
      [ "TOTAL 8.43", :total ],
      [ "VISA 8.43", :payment ],
      [ "THANK YOU", :other ]
    ])
  end

  it "reads the tax rate" do
    expect(classify("SUBTOTAL 10.00", "HST 13% 1.30").classified.last.rate).to eq(13.0)
    expect(classify("SUBTOTAL 10.00", "TVQ 9,975 % 1.00").classified.last.rate).to eq(9.975)
    expect(classify("SUBTOTAL 10.00", "GST 0.50").classified.last.rate).to be_nil
  end

  it "classifies French keywords" do
    expect(kinds("PAIN 3.49", "SOUS-TOTAL 3.49", "TPS 0.17", "TVQ 0.35", "MONTANT TOTAL 4.01", "INTERAC 4.01"))
      .to eq([
        [ "PAIN 3.49", :item ], [ "SOUS-TOTAL 3.49", :subtotal ], [ "TPS 0.17", :tax ],
        [ "TVQ 0.35", :tax ], [ "MONTANT TOTAL 4.01", :total ], [ "INTERAC 4.01", :payment ]
      ])
  end

  it "doesn't take SUB TOTAL as a total, or totals of savings and item counts" do
    expect(kinds("ITEM 1.00", "SUB TOTAL 1.00", "TOTAL SAVINGS 2.00", "TOTAL NUMBER OF ITEMS SOLD 3", "BALANCE DUE 1.00"))
      .to eq([
        [ "ITEM 1.00", :item ], [ "SUB TOTAL 1.00", :subtotal ], [ "TOTAL SAVINGS 2.00", :other ],
        [ "TOTAL NUMBER OF ITEMS SOLD 3", :other ], [ "BALANCE DUE 1.00", :total ]
      ])
  end

  it "keeps a TOTAL TAX summary out of the taxes" do
    expect(kinds("ITEM 1.00", "HST 0.13", "TOTAL TAX 0.13", "TOTAL 1.13"))
      .to eq([ [ "ITEM 1.00", :item ], [ "HST 0.13", :tax ], [ "TOTAL TAX 0.13", :other ], [ "TOTAL 1.13", :total ] ])
  end

  it "only takes rows above the subtotal as items" do
    expect(kinds("ITEM 1.00", "SUBTOTAL 1.00", "LOYALTY POINTS 25.00").last).to eq([ "LOYALTY POINTS 25.00", :other ])
  end

  it "ends the item region at the first tax or total when there's no subtotal" do
    expect(kinds("COFFEE 2.10", "GST 0.11", "TOTAL 2.21", "CHANGE DUE 0.00", "REWARDS 10.00"))
      .to eq([
        [ "COFFEE 2.10", :item ], [ "GST 0.11", :tax ], [ "TOTAL 2.21", :total ],
        [ "CHANGE DUE 0.00", :payment ], [ "REWARDS 10.00", :other ]
      ])
  end

  it "keeps rows without an amount as other" do
    expect(kinds("BANANAS", "0.97").first).to eq([ "BANANAS", :other ])
  end

  it "marks a row that only states a quantity as a quantity row" do
    result = classify("2 @ 3.99", "COKE 7.98", "1.234 kg @ $0.79/kg", "BANANAS 0.97", "SUBTOTAL 8.95").classified
    expect(result.map(&:kind)).to eq(%i[quantity item quantity item subtotal])
    expect(result[0].quantity).to eq(ReceiptParser::Quantity.new(qty: 2, unit_price: 399))
    expect(result[2].quantity).to eq(ReceiptParser::Quantity.new(qty: BigDecimal("1.234"), unit_price: 79))
  end

  it "reads weight units in capitals, as most tills print them" do
    result = classify("1.234 KG @ $0.79/KG", "BANANAS 0.97", "2.5 LB @ 1.99", "APPLES 4.98", "SUBTOTAL 5.95").classified
    expect(result.map(&:kind)).to eq(%i[quantity item quantity item subtotal])
    expect(result[0].quantity).to eq(ReceiptParser::Quantity.new(qty: BigDecimal("1.234"), unit_price: 79))
  end

  it "records a quantity printed on the item's own row" do
    row = classify("COKE 2 x 3.99 7.98", "SUBTOTAL 7.98").classified.first
    expect(row.kind).to eq(:item)
    expect(row.quantity).to eq(ReceiptParser::Quantity.new(qty: 2, unit_price: 399))
  end

  it "reads a multi-buy price as a unit price" do
    row = classify("3/$5.00", "YOGURT 3.34", "SUBTOTAL 3.34").classified.first
    expect(row.kind).to eq(:quantity)
    expect(row.quantity).to eq(ReceiptParser::Quantity.new(qty: nil, unit_price: BigDecimal("500") / 3))
  end

  it "takes discount rows in the item region as items" do
    expect(kinds("TV 499.99", "TPD/1234567 50.00-", "SUBTOTAL 449.99")[1]).to eq([ "TPD/1234567 50.00-", :item ])
  end

  it "finds the card's last four digits" do
    expect(classify("VISA ************4242 8.43").card_last_four).to eq("4242")
    expect(classify("MC XXXXXXXXXXXX1234").card_last_four).to eq("1234")
    expect(classify("CARD # **** **** **** 4321").card_last_four).to eq("4321")
    expect(classify("TOTAL 8.43").card_last_four).to be_nil
  end

  it "finds the last four when Vision collapses or splits the mask on a payment row" do
    # Vision reads long runs of * or X as a few characters, sometimes split in two.
    expect(classify("VISA ** **4242 20.29").card_last_four).to eq("4242")
    expect(classify("VISA *4242 20.29").card_last_four).to eq("4242")
    expect(classify("MC XXX> XXX1234 37.94").card_last_four).to eq("1234")
  end

  it "doesn't take a short mask off a payment row" do
    expect(classify("ITEM *1234 5.00", "SUBTOTAL 5.00").card_last_four).to be_nil
    expect(classify("AUTH 123456").card_last_four).to be_nil
  end
end
