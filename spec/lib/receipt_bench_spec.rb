# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReceiptBench do
  let(:dir) { Pathname(Dir.mktmpdir) }
  let(:capture) { JSON.parse(Rails.root.join("spec/fixtures/contract/create_receipt.request.json").read) }
  let(:expected) { JSON.parse(Rails.root.join("spec/fixtures/receipts/contract_loblaws.expected.json").read) }

  after { FileUtils.remove_entry(dir) }

  def write(name, data) = dir.join(name).write(JSON.generate(data))

  before do
    write("loblaws.expected.json", expected)
    write("loblaws.none.ocr.json", capture.deep_merge("ocr" => { "preprocessing" => "none", "page_ms" => [ 400 ] }))
    # The gray variant "read" the total row wrong and lost a line's confidence.
    lines = capture["ocr_lines"].map { it["text"] == "TOTAL" ? it.merge("text" => "T0TAI") : it }
    lines[1] = lines[1].merge("confidence" => 0.5)
    write("loblaws.gray_only.ocr.json", capture.merge("ocr_lines" => lines, "ocr" => { "page_ms" => [ 500, 700 ] }))
  end

  subject(:report) { described_class.new(dir).run }

  it "scores each variant" do
    none = report.variants.fetch("none")
    expect(none).to have_attributes(receipts: 1, total_correct: 1, items_found: 2, items_expected: 2, parsed: 1, mean_page_ms: 400.0)
    expect(none.low_confidence_share).to be_within(0.001).of(1.0 / 15)

    gray = report.variants.fetch("gray_only")
    expect(gray).to have_attributes(receipts: 1, total_correct: 0, parsed: 0, mean_page_ms: 600.0)
    expect(gray.low_confidence_share).to be_within(0.001).of(2.0 / 15)
  end

  it "charges each wrong field to the step that writes it" do
    expect(report.variants.fetch("gray_only").blame).to eq({ "PickTotal" => { "total" => 1 } })
    expect(report.variants.fetch("none").blame).to eq({})
  end

  it "fuzzy-matches item descriptions but needs the exact line total" do
    expect(described_class.item_found?({ "description" => "PC MILK 2% 4L", "line_total" => 649 },
      [ ReceiptParser::Item.new(description: "PC MlLK 2% 4L", qty: 1, unit_price: 649, line_total: 649, sku: nil) ])).to be(true)
    expect(described_class.item_found?({ "description" => "PC MILK 2% 4L", "line_total" => 649 },
      [ ReceiptParser::Item.new(description: "PC MILK 2% 4L", qty: 1, unit_price: 648, line_total: 648, sku: nil) ])).to be(false)
    expect(described_class.item_found?({ "description" => "PC MILK 2% 4L", "line_total" => 649 },
      [ ReceiptParser::Item.new(description: "BANANAS", qty: 1, unit_price: 649, line_total: 649, sku: nil) ])).to be(false)
  end

  it "prints one row per variant and the blame lines" do
    text = report.to_s
    expect(text.lines.grep(/\A(none|gray_only)\s/).size).to eq(2)
    expect(text).to include("gray_only: total wrong on 1 receipt → PickTotal")
  end

  it "skips captures that have no expected file" do
    write("other.none.ocr.json", capture)
    expect(report.variants.fetch("none").receipts).to eq(1)
    expect(report.skipped).to eq([ "other.none.ocr.json" ])
  end
end
