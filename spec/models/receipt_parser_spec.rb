# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReceiptParser do
  corpus = Rails.root.join("spec/fixtures/receipts")

  corpus.glob("*.expected.json").sort.each do |expected_path|
    name = expected_path.basename.to_s.delete_suffix(".expected.json")

    describe name do
      let(:capture) { JSON.parse(corpus.join("#{name}.ocr.json").read) }
      let(:expected) { JSON.parse(expected_path.read) }
      let(:result) { described_class.call(ocr_lines: capture["ocr_lines"], captured_at: Time.iso8601(capture["captured_at"])) }

      %w[merchant subtotal tax total card_last_four].each do |field|
        it "finds the #{field}" do
          skip "not in #{name}.expected.json" unless expected.key?(field)
          expect(result.public_send(field)).to eq(expected[field])
        end
      end

      it "finds the date and time" do
        expect(result.purchased_on&.iso8601).to eq(expected["purchased_on"]) if expected.key?("purchased_on")
        if expected.key?("purchased_at")
          expect(result.purchased_at).to eq(expected["purchased_at"] && Time.iso8601(expected["purchased_at"]))
        end
      end

      it "finds the items" do
        skip "not in #{name}.expected.json" unless expected.key?("items")
        actual = result.items.map do |item|
          { "description" => item.description, "qty" => item.qty.to_f, "unit_price" => item.unit_price, "line_total" => item.line_total }
        end
        expect(actual).to eq(expected["items"].map { it.merge("qty" => it["qty"].to_f) })
      end

      it "gets the expected status" do
        skip "not in #{name}.expected.json" unless expected.key?("parse_status")
        reasons = ReceiptValidator.for_result(result, confidences: capture["ocr_lines"].map { it["confidence"] })
        expect(reasons.empty? ? "parsed" : "needs_review").to eq(expected["parse_status"]), "review reasons: #{reasons}"
      end
    end
  end
end
