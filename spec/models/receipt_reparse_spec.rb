# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Receipt re-parsing" do
  let(:capture) { JSON.parse(Rails.root.join("spec/fixtures/contract/create_receipt.request.json").read) }

  def receipt(**attrs)
    Receipt.create!(
      capture_id: SecureRandom.uuid, parse_status: "failed", raw_text: capture["raw_text"],
      ocr_lines: capture["ocr_lines"], captured_at: capture["captured_at"],
      images: [ { io: StringIO.new(file_fixture("page.jpg").binread), filename: "p.jpg", content_type: "image/jpeg" } ],
      **attrs
    )
  end

  describe ".needing_reparse" do
    it "finds unconfirmed receipts parsed by an older parser, or never parsed" do
      old = receipt(parse_status: "needs_review", parser_version: ReceiptParser::VERSION - 1)
      never = receipt(parser_version: nil)
      receipt(parse_status: "parsed", parser_version: ReceiptParser::VERSION)
      receipt(parse_status: "confirmed", parser_version: ReceiptParser::VERSION - 1)

      expect(Receipt.needing_reparse).to contain_exactly(old, never)
    end
  end

  describe "#reparse!" do
    it "parses again and applies the result" do
      r = receipt(parser_version: ReceiptParser::VERSION - 1)
      expect(r.reparse!).to eq(:reparsed)
      expect(r.reload).to have_attributes(parse_status: "parsed", total: 843, parser_version: ReceiptParser::VERSION)
    end

    it "skips a confirmed receipt" do
      r = receipt(parse_status: "confirmed", merchant: "Mine", parsed: { "total" => 1 })
      expect(r.reparse!).to eq(:skipped)
      expect(r.reload.parsed).to eq("total" => 1)
    end

    it "with force, rewrites only `parsed` on a confirmed receipt" do
      r = receipt(parse_status: "confirmed", merchant: "Mine", total: 1, parsed: { "total" => 1 }, parser_version: 0)
      expect(r.reparse!(force: true)).to eq(:parsed_only)
      expect(r.reload).to have_attributes(merchant: "Mine", total: 1, parse_status: "confirmed", parser_version: ReceiptParser::VERSION)
      expect(r.parsed["total"]).to eq(843)
      expect(r.line_items).to be_empty
    end

    it "records a parser failure" do
      r = receipt(parse_status: "parsed", parser_version: 0)
      allow(ReceiptParser).to receive(:call).and_raise(ReceiptParser::StepError.new(ReceiptParser::Steps::BuildRows, RuntimeError.new("x")))
      expect(r.reparse!).to eq(:failed)
      expect(r.reload.parsed["failed_step"]).to eq("BuildRows")
    end

    it "records the failure when the result itself can't be saved" do
      r = receipt(parse_status: "parsed", parser_version: 0)
      result = ReceiptParser.call(ocr_lines: r.ocr_lines, captured_at: r.captured_at)
      allow(ReceiptParser).to receive(:call).and_return(result.with(total: 9_999_999_999))

      expect(r.reparse!).to eq(:failed)
      expect(r.reload).to have_attributes(parse_status: "failed", total: nil)
      expect(r.parsed["error"]).to be_present
    end
  end
end
