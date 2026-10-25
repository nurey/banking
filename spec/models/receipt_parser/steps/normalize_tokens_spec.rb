# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReceiptParser::Steps::NormalizeTokens do
  def normalize(text)
    row = ReceiptParser::Row.new(
      page: 0, y: 0.1, height: 0.02, money: [],
      cells: [ ReceiptParser::Line.new(page: 0, text:, x: 0.1, y: 0.1, w: 0.5, h: 0.02, confidence: 1.0) ]
    )
    described_class.new.call(context(rows: [ row ])).rows.first
  end

  it "fixes letter/digit mix-ups inside number-like tokens" do
    expect(normalize("MILK 12.O0").text).to eq("MILK 12.00")
    expect(normalize("EGGS l.99").text).to eq("EGGS 1.99")
    expect(normalize("BREAD 3.4S").text).to eq("BREAD 3.45")
    expect(normalize("CHEESE B.99").text).to eq("CHEESE 8.99")
    expect(normalize("JAM |0.00").text).to eq("JAM 10.00")
    expect(normalize("TOTAL 2I.o5").text).to eq("TOTAL 21.05")
  end

  it "leaves words alone" do
    expect(normalize("BOB'S SOLO SODA").text).to eq("BOB'S SOLO SODA")
    expect(normalize("PC MILK 2% 4L").text).to eq("PC MILK 2% 4L")
    expect(normalize("APPLES 10lb").text).to eq("APPLES 10lb")
  end

  it "takes the right-most money token as the row's amount, in cents" do
    row = normalize("2 @ 3.99 7.98")
    expect(row.money).to eq([ 399, 798 ])
    expect(row.amount).to eq(798)
  end

  it "reads a comma decimal mark and a dollar sign" do
    expect(normalize("TOTAL $23,45").amount).to eq(2345)
  end

  it "reads leading and trailing minus signs as negative" do
    expect(normalize("TPD/1234567 5.00-").amount).to eq(-500)
    expect(normalize("COUPON -1.50").amount).to eq(-150)
  end

  it "reads thousands separators" do
    expect(normalize("TOTAL 1,234.56").amount).to eq(123_456)
  end

  it "doesn't read percentages, weights, or long numbers as money" do
    expect(normalize("HST 13.00%").money).to eq([])
    expect(normalize("1.234 kg").money).to eq([])
    expect(normalize("REF 123456.789").money).to eq([])
  end

  it "has no amount when there is no money token" do
    expect(normalize("THANK YOU").amount).to be_nil
  end
end
