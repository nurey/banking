# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReceiptParser::Steps::BuildRows do
  def build(*lines)
    described_class.new.call(context(ocr_lines: lines)).rows
  end

  it "joins a description and a price that Vision split onto one row" do
    result = build(
      ocr_line("0.97", x: 0.82, y: 0.231, w: 0.1, h: 0.019),
      ocr_line("BANANAS", x: 0.08, y: 0.230, w: 0.2, h: 0.018)
    )
    expect(result.map(&:text)).to eq([ "BANANAS 0.97" ])
  end

  it "keeps lines a full line height apart on separate rows, top to bottom" do
    result = build(
      ocr_line("MILK 6.49", y: 0.26),
      ocr_line("BANANAS 0.97", y: 0.23)
    )
    expect(result.map(&:text)).to eq([ "BANANAS 0.97", "MILK 6.49" ])
  end

  it "tolerates skew of less than half a line height" do
    result = build(
      ocr_line("BANANAS", x: 0.08, y: 0.230),
      ocr_line("0.97", x: 0.82, y: 0.238),
      ocr_line("MILK", x: 0.08, y: 0.260),
      ocr_line("6.49", x: 0.82, y: 0.268)
    )
    expect(result.map(&:text)).to eq([ "BANANAS 0.97", "MILK 6.49" ])
  end

  it "straightens a page skewed by more than half a line height across its width" do
    # 2°: the right column sits 0.03 lower than the left, more than the 0.01 tolerance.
    slope = Math.tan(2 * Math::PI / 180)
    lines = %w[BANANAS MILK BREAD SUBTOTAL HST TOTAL].each_with_index.flat_map do |label, i|
      y = 0.2 + i * 0.04
      [
        ocr_line(label, x: 0.08, y: y + slope * 0.08, w: 0.2, h: 0.02),
        ocr_line(format("%.2f", i + 1), x: 0.82, y: y + slope * 0.87, w: 0.1, h: 0.02)
      ]
    end
    expect(build(*lines).map(&:text)).to eq([
      "BANANAS 1.00", "MILK 2.00", "BREAD 3.00", "SUBTOTAL 4.00", "HST 5.00", "TOTAL 6.00"
    ])
  end

  it "leaves an unskewed page's rows alone when one row's lines straddle another" do
    result = build(
      ocr_line("TOTAL", x: 0.08, y: 0.400),
      ocr_line("8.43", x: 0.82, y: 0.401),
      ocr_line("VISA 8.43", x: 0.08, y: 0.430)
    )
    expect(result.map(&:text)).to eq([ "TOTAL 8.43", "VISA 8.43" ])
  end

  it "orders the cells of a row left to right across two columns" do
    result = build(
      ocr_line("6.49", x: 0.85, y: 0.30),
      ocr_line("MILK", x: 0.05, y: 0.30),
      ocr_line("H", x: 0.95, y: 0.30, w: 0.02),
      ocr_line("2% 4L", x: 0.30, y: 0.30)
    )
    expect(result.map(&:text)).to eq([ "MILK 2% 4L 6.49 H" ])
  end

  it "keeps pages apart and in page order" do
    result = build(
      ocr_line("TOTAL 8.43", y: 0.1, page: 1),
      ocr_line("LOBLAWS", y: 0.1, page: 0)
    )
    expect(result.map { [ it.page, it.text ] }).to eq([ [ 0, "LOBLAWS" ], [ 1, "TOTAL 8.43" ] ])
  end

  it "returns no rows for no lines" do
    expect(build).to eq([])
  end
end
