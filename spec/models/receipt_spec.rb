# frozen_string_literal: true

require "rails_helper"

RSpec.describe Receipt do
  def upload(name, content_type: nil, filename: name)
    path = file_fixture(name)
    content_type ||= Marcel::MimeType.for(path)
    { io: StringIO.new(path.binread), filename:, content_type: }
  end

  def build_receipt(images: [ upload("page.jpg") ], **attrs)
    described_class.new(
      capture_id: SecureRandom.uuid,
      parse_status: "failed",
      raw_text: "TOTAL 1.00",
      ocr_lines: [ { "page" => 0, "text" => "TOTAL 1.00", "x" => 0.1, "y" => 0.1, "w" => 0.5, "h" => 0.02, "confidence" => 1.0 } ],
      images:,
      **attrs
    )
  end

  describe "validations" do
    it "is valid with one JPEG page" do
      expect(build_receipt).to be_valid
    end

    it "requires capture_id, raw_text and ocr_lines" do
      receipt = build_receipt(capture_id: nil, raw_text: nil, ocr_lines: nil)
      expect(receipt).not_to be_valid
      expect(receipt.errors.attribute_names).to include(:capture_id, :raw_text, :ocr_lines)
    end

    it "allows empty OCR, for a scan Vision found no text on" do
      expect(build_receipt(raw_text: "", ocr_lines: [])).to be_valid
    end

    it "rejects a duplicate capture_id" do
      first = build_receipt
      first.save!
      expect(build_receipt(capture_id: first.capture_id)).not_to be_valid
    end

    it "rejects an unknown parse_status" do
      expect(build_receipt(parse_status: "bogus")).not_to be_valid
    end

    it "accepts a HEIC page" do
      expect(build_receipt(images: [ upload("page.heic") ])).to be_valid
    end

    it "requires at least one page" do
      receipt = build_receipt(images: [])
      expect(receipt).not_to be_valid
      expect(receipt.errors[:images]).to be_present
    end

    it "allows at most eight pages" do
      expect(build_receipt(images: Array.new(8) { upload("page.jpg") })).to be_valid
      expect(build_receipt(images: Array.new(9) { upload("page.jpg") })).not_to be_valid
    end

    it "rejects a page over 8 MB" do
      big = "\xFF\xD8\xFF".b + ("\0".b * 8.megabytes)
      receipt = build_receipt(images: [ { io: StringIO.new(big), filename: "big.jpg", content_type: "image/jpeg" } ])
      expect(receipt).not_to be_valid
      expect(receipt.errors[:images].join).to include("8 MB")
    end

    it "rejects a PNG page" do
      expect(build_receipt(images: [ upload("thumbnail.png") ])).not_to be_valid
    end

    it "rejects non-image bytes named x.jpg and declared as image/jpeg" do
      receipt = build_receipt(images: [ upload("fake.jpg", content_type: "image/jpeg", filename: "x.jpg") ])
      expect(receipt).not_to be_valid
      expect(receipt.errors[:images]).to be_present
    end

    it "accepts no thumbnail" do
      expect(build_receipt.thumbnail).not_to be_attached
      expect(build_receipt).to be_valid
    end

    it "accepts a small JPEG thumbnail" do
      expect(build_receipt(thumbnail: upload("thumbnail.jpg"))).to be_valid
    end

    it "rejects a PNG thumbnail" do
      receipt = build_receipt(thumbnail: upload("thumbnail.png"))
      expect(receipt).not_to be_valid
      expect(receipt.errors[:thumbnail]).to be_present
    end

    it "rejects a thumbnail over 256 KB" do
      big = "\xFF\xD8\xFF".b + ("\0".b * 256.kilobytes)
      receipt = build_receipt(thumbnail: { io: StringIO.new(big), filename: "t.jpg", content_type: "image/jpeg" })
      expect(receipt).not_to be_valid
      expect(receipt.errors[:thumbnail].join).to include("256 KB")
    end

    it "rejects a thumbnail with non-JPEG bytes" do
      receipt = build_receipt(thumbnail: upload("fake.jpg", content_type: "image/jpeg", filename: "t.jpg"))
      expect(receipt).not_to be_valid
    end
  end

  describe "#to_param" do
    it "is the capture_id" do
      receipt = build_receipt
      expect(receipt.to_param).to eq(receipt.capture_id)
    end
  end

  describe "#as_api_json" do
    let(:contract) { JSON.parse(file_fixture("../contract/receipt.response.json").read) }

    it "has exactly the contract's keys" do
      receipt = build_receipt(thumbnail: upload("thumbnail.jpg"))
      receipt.save!
      receipt.line_items.create!(position: 0, description: "BANANAS", qty: 1.234, unit_price: 79, line_total: 97)
      json = receipt.reload.as_api_json.deep_stringify_keys

      expect(json.keys).to match_array(contract.keys)
      expect(json["items"].first.keys).to match_array(contract["items"].first.keys)
      expect(json["images"].first.keys).to match_array(contract["images"].first.keys)
      expect(json["thumbnail"].keys).to match_array(contract["thumbnail"].keys)
    end

    it "builds every URL from the capture_id" do
      receipt = build_receipt(images: [ upload("page.jpg"), upload("page.heic") ], thumbnail: upload("thumbnail.jpg"))
      receipt.save!
      json = receipt.as_api_json

      expect(json[:images].map { it[:url] }).to eq([
        "/api/receipts/#{receipt.capture_id}/images/0",
        "/api/receipts/#{receipt.capture_id}/images/1"
      ])
      expect(json[:images].map { it[:page] }).to eq([ 0, 1 ])
      expect(json[:thumbnail][:url]).to eq("/api/receipts/#{receipt.capture_id}/thumbnail")
    end

    it "has a null thumbnail when none was sent" do
      receipt = build_receipt
      receipt.save!
      expect(receipt.as_api_json[:thumbnail]).to be_nil
    end

    it "serializes qty as a number and timestamps as ISO 8601" do
      receipt = build_receipt(purchased_at: Time.zone.parse("2026-10-24T11:40:00-04:00"))
      receipt.save!
      receipt.line_items.create!(position: 0, description: "MILK", qty: 1, unit_price: 649, line_total: 649)
      json = JSON.parse(receipt.reload.as_api_json.to_json)

      expect(json["items"].first["qty"]).to eq(1.0)
      expect(json["purchased_at"]).to match(/\A2026-10-24T\d\d:40:00(Z|[+-]\d\d:\d\d)\z/)
      expect(Time.iso8601(json["purchased_at"])).to eq(Time.iso8601("2026-10-24T11:40:00-04:00"))
    end
  end

  describe "#apply_parse" do
    let(:capture) { JSON.parse(file_fixture("../contract/create_receipt.request.json").read) }
    let(:receipt) do
      build_receipt(raw_text: capture["raw_text"], ocr_lines: capture["ocr_lines"], captured_at: capture["captured_at"]).tap(&:save!)
    end
    let(:result) { ReceiptParser.call(ocr_lines: receipt.ocr_lines, captured_at: receipt.captured_at) }

    it "writes the parsed fields, items, status and the parser's raw output" do
      receipt.apply_parse(result)
      receipt.reload

      expect(receipt).to have_attributes(
        merchant: "Loblaws", purchased_on: Date.new(2026, 10, 24), subtotal: 746, tax: 97, total: 843,
        card_last_four: "4242", parse_status: "parsed", review_reasons: [], parser_version: ReceiptParser::VERSION
      )
      expect(receipt.taxes).to eq([ { "label" => "HST", "rate" => 13.0, "amount" => 97 } ])
      expect(receipt.line_items.map { [ it.position, it.description, it.qty.to_f, it.unit_price, it.line_total ] })
        .to eq([ [ 0, "BANANAS", 1.234, 79, 97 ], [ 1, "PC MILK 2% 4L", 1.0, 649, 649 ] ])
      expect(receipt.parsed["total"]).to eq(843)
      expect(receipt.parsed["trace"].map { it["step"] }).to include("BuildRows", "PickTotal")
    end

    it "sets needs_review with the validator's reasons" do
      lines = receipt.ocr_lines.reject { it["text"] == "TOTAL" || it["y"] == 0.401 }
      receipt.update!(ocr_lines: lines)
      receipt.apply_parse(ReceiptParser.call(ocr_lines: lines, captured_at: receipt.captured_at))

      expect(receipt.reload.parse_status).to eq("needs_review")
      expect(receipt.review_reasons).to include("total_missing")
    end

    it "replaces the line items when parsed again" do
      receipt.apply_parse(result)
      receipt.apply_parse(result)
      expect(receipt.reload.line_items.size).to eq(2)
    end

    it "does nothing to a confirmed receipt" do
      receipt.update!(parse_status: "confirmed", merchant: "Mine", confirmed_at: Time.current)
      receipt.apply_parse(result)

      expect(receipt.reload).to have_attributes(merchant: "Mine", parse_status: "confirmed", parser_version: nil)
      expect(receipt.line_items).to be_empty
    end
  end

  describe "#record_parse_failure" do
    it "keeps the status failed and stores the failing step" do
      receipt = build_receipt.tap(&:save!)
      error = ReceiptParser::StepError.new(ReceiptParser::Steps::PickTotal, RuntimeError.new("boom"))
      receipt.record_parse_failure(error)

      expect(receipt.reload.parse_status).to eq("failed")
      expect(receipt.parsed).to include("failed_step" => "PickTotal", "error" => "PickTotal failed: boom")
      expect(receipt.parser_version).to eq(ReceiptParser::VERSION)
    end
  end

  describe "#revalidate!" do
    it "checks the current, possibly edited, values" do
      receipt = build_receipt(subtotal: 100, tax: 13, total: 113, purchased_on: Date.new(2026, 10, 24)).tap(&:save!)
      receipt.line_items.create!(position: 0, description: "A", qty: 1, unit_price: 100, line_total: 100)

      receipt.revalidate!
      expect(receipt.reload).to have_attributes(parse_status: "parsed", review_reasons: [])

      receipt.update!(total: 200)
      receipt.revalidate!
      expect(receipt.reload).to have_attributes(parse_status: "needs_review", review_reasons: [ "totals_mismatch" ])
    end
  end
end
