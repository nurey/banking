# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReceiptParser::Steps::ExtractItems do
  def extract(*classified_rows)
    described_class.new.call(context(classified: classified_rows))
  end

  def item(description, qty, unit_price, line_total, sku: nil)
    ReceiptParser::Item.new(description:, qty:, unit_price:, line_total:, sku:)
  end

  it "turns item rows into items with qty 1" do
    result = extract(classified("BANANAS 0.97", :item), classified("PC MILK 2% 4L 6.49 H", :item))
    expect(result.items).to eq([ item("BANANAS", 1, 97, 97), item("PC MILK 2% 4L", 1, 649, 649) ])
  end

  it "applies a quantity row above the item" do
    result = extract(
      classified("1.234 kg @ $0.79/kg", :quantity, quantity: ReceiptParser::Quantity.new(qty: BigDecimal("1.234"), unit_price: 79)),
      classified("BANANAS 0.97", :item)
    )
    expect(result.items).to eq([ item("BANANAS", BigDecimal("1.234"), 79, 97) ])
  end

  it "applies a quantity row below the item when it matches that item's total" do
    result = extract(
      classified("COKE 7.98", :item),
      classified("2 @ 3.99", :quantity, quantity: ReceiptParser::Quantity.new(qty: 2, unit_price: 399)),
      classified("CHIPS 3.49", :item)
    )
    expect(result.items).to eq([ item("COKE", 2, 399, 798), item("CHIPS", 1, 349, 349) ])
  end

  it "prefers the item below when the quantity row explains both" do
    result = extract(
      classified("COKE 7.98", :item),
      classified("2 @ 3.99", :quantity, quantity: ReceiptParser::Quantity.new(qty: 2, unit_price: 399)),
      classified("PEPSI 7.98", :item)
    )
    expect(result.items.map { [ it.description, it.qty ] }).to eq([ [ "COKE", 1 ], [ "PEPSI", 2 ] ])
  end

  it "uses a quantity printed on the item's own row" do
    result = extract(classified("COKE 2 x 3.99 7.98", :item, quantity: ReceiptParser::Quantity.new(qty: 2, unit_price: 399)))
    expect(result.items).to eq([ item("COKE", 2, 399, 798) ])
  end

  it "works out the count from a multi-buy price" do
    result = extract(
      classified("3/$5.00", :quantity, quantity: ReceiptParser::Quantity.new(qty: nil, unit_price: BigDecimal("500") / 3)),
      classified("YOGURT 3.34", :item)
    )
    expect(result.items).to eq([ item("YOGURT", 2, 167, 334) ])
  end

  it "takes the description from the row above when the price row has none" do
    result = extract(classified("ORGANIC BANANAS", :other), classified("0.97", :item))
    expect(result.items).to eq([ item("ORGANIC BANANAS", 1, 97, 97) ])
  end

  it "keeps a leading SKU apart from the description" do
    result = extract(classified("1234567 KIRKLAND TOWELS 23.99 Y", :item))
    expect(result.items).to eq([ item("KIRKLAND TOWELS", 1, 2399, 2399, sku: "1234567") ])
  end

  it "makes discount rows negative items" do
    result = extract(classified("TPD/1234567 5.00-", :item), classified("COUPON 1.50", :item))
    expect(result.items.map(&:line_total)).to eq([ -500, -150 ])
    expect(result.items.first.unit_price).to eq(-500)
  end

  it "takes the subtotal row's amount" do
    expect(extract(classified("ITEM 1.00", :item), classified("SUBTOTAL 1.00", :subtotal)).subtotal).to eq(100)
    expect(extract(classified("ITEM 1.00", :item)).subtotal).to be_nil
  end
end
