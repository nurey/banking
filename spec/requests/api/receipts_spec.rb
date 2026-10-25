# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/api/receipts" do
  let(:token) { "test-receipts-token" }
  let(:auth) { { "Authorization" => "Bearer #{token}" } }
  let(:contract_dir) { Rails.root.join("spec/fixtures/contract") }
  let(:capture) { JSON.parse(contract_dir.join("create_receipt.request.json").read) }
  let(:capture_id) { capture["capture_id"] }

  around do |example|
    previous = ENV["RECEIPTS_API_TOKEN"]
    ENV["RECEIPTS_API_TOKEN"] = token
    example.run
  ensure
    ENV["RECEIPTS_API_TOKEN"] = previous
  end

  def json = JSON.parse(response.body)

  def page_upload(name = "page.jpg", type = "image/jpeg") = fixture_file_upload(name, type)

  def post_capture(document = capture, images: [ page_upload ], thumbnail: nil, headers: auth)
    params = { receipt: document.is_a?(String) ? document : document.to_json }
    params[:images] = images unless images.nil?
    params[:thumbnail] = thumbnail if thumbnail
    post "/api/receipts", params:, headers:
  end

  def create_receipt(document = capture, **options)
    post_capture(document, **options)
    expect(response).to have_http_status(:created), response.body
    Receipt.find_by!(capture_id: document["capture_id"])
  end

  # Rows straight into the table: fast, and enough for listing.
  def insert_receipts(count, created_at: Time.current, **attrs)
    rows = Array.new(count) do |i|
      {
        capture_id: SecureRandom.uuid, parse_status: "parsed", raw_text: "x", ocr_lines: [],
        created_at: created_at.is_a?(Proc) ? created_at.call(i) : created_at, updated_at: Time.current, **attrs
      }
    end
    Receipt.insert_all!(rows)
  end

  describe "authentication" do
    it "refuses a request without a token" do
      get "/api/receipts"
      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq("errors" => [ "Token rejected" ])
      expect(response.headers["WWW-Authenticate"]).to start_with("Token")
    end

    it "refuses a wrong token" do
      get "/api/receipts", headers: { "Authorization" => "Bearer nope" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses every request when RECEIPTS_API_TOKEN is unset" do
      ENV.delete("RECEIPTS_API_TOKEN")
      get "/api/receipts", headers: { "Authorization" => "Bearer " }
      expect(response).to have_http_status(:unauthorized)
      get "/api/receipts", headers: auth
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses an upload without a token and stores nothing" do
      post_capture(headers: {})
      expect(response).to have_http_status(:unauthorized)
      expect(Receipt.count).to eq(0)
    end

    it "doesn't draw the Active Storage routes" do
      receipt = create_receipt
      blob = receipt.images.first.blob
      get "/rails/active_storage/blobs/redirect/#{blob.signed_id}/page.jpg"
      expect(response).to have_http_status(:not_found)
      expect { Rails.application.routes.url_helpers.rails_blob_path(blob) }.to raise_error(NoMethodError)
    end
  end

  describe "POST /api/receipts" do
    it "creates the receipt, attaches the pages, and parses it" do
      post_capture(images: [ page_upload, page_upload("page.heic", "image/heic") ])

      expect(response).to have_http_status(:created)
      contract = JSON.parse(contract_dir.join("receipt.response.json").read)
      expect(json.keys).to match_array(contract.keys)
      expect(json).to include(
        "capture_id" => capture_id, "parse_status" => "parsed", "merchant" => "Loblaws", "total" => 843,
        "purchased_on" => "2026-10-24", "card_last_four" => "0298", "thumbnail" => nil
      )
      expect(json["images"].map { it.except("byte_size") }).to eq([
        { "page" => 0, "url" => "/api/receipts/#{capture_id}/images/0" },
        { "page" => 1, "url" => "/api/receipts/#{capture_id}/images/1" }
      ])

      receipt = Receipt.find_by!(capture_id:)
      expect(receipt.images.size).to eq(2)
      expect(receipt.metadata).to eq("ocr" => capture["ocr"], "device" => capture["device"])
      expect(receipt.raw_text).to eq(capture["raw_text"])
    end

    it "returns the existing receipt for a repeated capture_id without storing or parsing again" do
      receipt = create_receipt
      receipt.update!(merchant: "Edited")

      expect(ReceiptParser).not_to receive(:call)
      post_capture(images: [ page_upload, page_upload ])

      expect(response).to have_http_status(:ok)
      expect(json).to include("id" => receipt.id, "merchant" => "Edited")
      expect(receipt.reload.images.size).to eq(1)
      expect(Receipt.count).to eq(1)
    end

    it "returns the existing receipt when a racing retry hits the uniqueness check" do
      receipt = create_receipt
      first_lookup = true
      allow(Receipt).to receive(:find_by).and_wrap_original do |original, *args, **kwargs|
        first_lookup ? (first_lookup = false) && nil : original.call(*args, **kwargs)
      end

      post_capture
      expect(response).to have_http_status(:ok)
      expect(json["id"]).to eq(receipt.id)
    end

    it "returns the existing receipt when a racing retry hits the unique index" do
      receipt = create_receipt
      first_lookup = true
      allow(Receipt).to receive(:find_by).and_wrap_original do |original, *args, **kwargs|
        first_lookup ? (first_lookup = false) && nil : original.call(*args, **kwargs)
      end
      allow_any_instance_of(Receipt).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique)

      post_capture
      expect(response).to have_http_status(:ok)
      expect(json["id"]).to eq(receipt.id)
    end

    it "accepts the multipart body the app builds, with a JSON part that has no filename" do
      boundary = "Boundary-#{SecureRandom.hex(8)}"
      body = +""
      body << "--#{boundary}\r\nContent-Disposition: form-data; name=\"receipt\"\r\n"
      body << "Content-Type: application/json\r\n\r\n#{capture.to_json}\r\n"
      body << "--#{boundary}\r\nContent-Disposition: form-data; name=\"images[]\"; filename=\"page-0.jpg\"\r\n"
      body << "Content-Type: image/jpeg\r\n\r\n".b + file_fixture("page.jpg").binread + "\r\n".b
      body << "--#{boundary}\r\nContent-Disposition: form-data; name=\"thumbnail\"; filename=\"thumbnail.jpg\"\r\n"
      body << "Content-Type: image/jpeg\r\n\r\n".b + file_fixture("thumbnail.jpg").binread + "\r\n".b
      body << "--#{boundary}--\r\n"

      post "/api/receipts", params: body.b,
        headers: auth.merge("Content-Type" => "multipart/form-data; boundary=#{boundary}")

      expect(response).to have_http_status(:created), response.body
      expect(json["thumbnail"]).to include("url" => "/api/receipts/#{capture_id}/thumbnail")
    end

    it "accepts the capture document as a file part, as curl -F receipt=@file sends it" do
      document = Rack::Test::UploadedFile.new(StringIO.new(capture.to_json), "application/json", original_filename: "receipt.json")
      post "/api/receipts", params: { receipt: document, images: [ page_upload ] }, headers: auth
      expect(response).to have_http_status(:created), response.body
    end

    it "copies only the listed fields from the capture document" do
      post_capture(capture.merge(
        "parse_status" => "confirmed", "confirmed_at" => "2026-10-24T12:00:00Z",
        "parsed" => { "total" => 1 }, "parser_version" => 99, "merchant" => "Spoofed", "id" => 12_345
      ))

      expect(response).to have_http_status(:created)
      receipt = Receipt.find_by!(capture_id:)
      expect(receipt.confirmed_at).to be_nil
      expect(receipt.parse_status).to eq("parsed")
      expect(receipt.parser_version).to eq(ReceiptParser::VERSION)
      expect(receipt.merchant).to eq("Loblaws")
      expect(receipt.parsed["total"]).to eq(843)
      expect(receipt.id).not_to eq(12_345)
    end

    it "keeps the receipt as failed when the parser raises" do
      error = ReceiptParser::StepError.new(ReceiptParser::Steps::PickTotal, NoMethodError.new("undefined method 'amount'"))
      allow(ReceiptParser).to receive(:call).and_raise(error)

      post_capture
      expect(response).to have_http_status(:created)
      expect(json["parse_status"]).to eq("failed")
      expect(Receipt.find_by!(capture_id:).parsed).to include("failed_step" => "PickTotal")
    end

    it "keeps the receipt as failed when the parser raises anything else" do
      allow(ReceiptParser).to receive(:call).and_raise(ArgumentError, "bad")
      post_capture
      expect(response).to have_http_status(:created)
      expect(json["parse_status"]).to eq("failed")
    end

    it "filters the capture document out of the request log" do
      io = StringIO.new
      logger = ActiveSupport::Logger.new(io)
      allow(ActionController::Base).to receive(:logger).and_return(logger)
      allow(ActionController::API).to receive(:logger).and_return(logger)
      allow(Rails).to receive(:logger).and_return(logger)

      post_capture(headers: {})

      log = io.string
      expect(log).to include("Parameters:")
      expect(log).to include("[FILTERED]")
      expect(log).not_to include("LOBLAWS")
      expect(log).not_to include("0298")
    end

    describe "thumbnail" do
      it "attaches a thumbnail when one is sent" do
        post_capture(thumbnail: fixture_file_upload("thumbnail.jpg", "image/jpeg"))
        expect(response).to have_http_status(:created)
        expect(json["thumbnail"]).to eq(
          "url" => "/api/receipts/#{capture_id}/thumbnail", "byte_size" => file_fixture("thumbnail.jpg").size
        )
      end

      it "rejects a PNG thumbnail" do
        post_capture(thumbnail: fixture_file_upload("thumbnail.png", "image/png"))
        expect(response).to have_http_status(:unprocessable_content)
        expect(json["errors"].join).to match(/thumbnail/i)
        expect(Receipt.count).to eq(0)
      end

      it "rejects a thumbnail over 256 KB" do
        big = Rack::Test::UploadedFile.new(
          StringIO.new("\xFF\xD8\xFF".b + ("\0".b * 256.kilobytes)), "image/jpeg", true, original_filename: "t.jpg"
        )
        post_capture(thumbnail: big)
        expect(response).to have_http_status(:unprocessable_content)
        expect(json["errors"].join).to match(/thumbnail/i)
      end
    end

    describe "limits and validation" do
      it "returns 413 for more than 5,000 OCR lines" do
        line = capture["ocr_lines"].first
        post_capture(capture.merge("ocr_lines" => Array.new(5_001) { line }))
        expect(response).to have_http_status(:content_too_large)
        expect(json["errors"]).to be_present
      end

      it "returns 413 for raw text over 200 KB" do
        post_capture(capture.merge("raw_text" => "x" * (200.kilobytes + 1)))
        expect(response).to have_http_status(:content_too_large)
      end

      it "returns 422 for a receipt part that isn't JSON" do
        post_capture("{not json")
        expect(response).to have_http_status(:unprocessable_content)
        expect(json["errors"]).to be_present
      end

      it "returns 422 for a JSON receipt part that isn't an object" do
        post_capture("[1, 2]")
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "returns 422 without a receipt part" do
        post "/api/receipts", params: { images: [ page_upload ] }, headers: auth
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "returns 422 without images" do
        post_capture(images: nil)
        expect(response).to have_http_status(:unprocessable_content)
        expect(json["errors"].join).to match(/images/i)
      end

      it "returns 422 for more than 8 images" do
        post_capture(images: Array.new(9) { page_upload })
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "returns 422 for images that aren't file parts" do
        post_capture(images: [ "not-a-file" ])
        expect(response).to have_http_status(:unprocessable_content)
        expect(Receipt.count).to eq(0)
      end

      it "returns 422 for a non-image part named x.jpg and sent as image/jpeg" do
        post_capture(images: [ fixture_file_upload("fake.jpg", "image/jpeg") ])
        expect(response).to have_http_status(:unprocessable_content)
        expect(Receipt.count).to eq(0)
      end

      it "returns 422 for an invalid capture_id" do
        post_capture(capture.merge("capture_id" => "42"))
        expect(response).to have_http_status(:unprocessable_content)
      end

      [
        [ "a missing text", ->(line) { line.except("text") } ],
        [ "a string page", ->(line) { line.merge("page" => "0") } ],
        [ "a negative page", ->(line) { line.merge("page" => -1) } ],
        [ "a string coordinate", ->(line) { line.merge("x" => "0.1") } ],
        [ "a missing confidence", ->(line) { line.except("confidence") } ],
        [ "a non-object line", ->(_line) { "TOTAL" } ]
      ].each do |description, change|
        it "returns 422 for an OCR line with #{description}" do
          lines = capture["ocr_lines"].dup
          lines[0] = change.call(lines[0])
          post_capture(capture.merge("ocr_lines" => lines))
          expect(response).to have_http_status(:unprocessable_content)
          expect(json["errors"].join).to match(/ocr_lines/)
        end
      end

      it "returns 422 for ocr_lines that aren't an array" do
        post_capture(capture.merge("ocr_lines" => { "page" => 0 }))
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "returns 422 for an OCR line on a page past the last image" do
        lines = capture["ocr_lines"].dup
        lines[0] = lines[0].merge("page" => 1)
        post_capture(capture.merge("ocr_lines" => lines))
        expect(response).to have_http_status(:unprocessable_content)
        expect(json["errors"].join).to match(/page/)
      end
    end
  end

  describe "GET /api/receipts/:capture_id" do
    it "returns the receipt by capture_id" do
      receipt = create_receipt
      get "/api/receipts/#{capture_id}", headers: auth
      expect(response).to have_http_status(:ok)
      expect(json).to eq(JSON.parse(receipt.reload.as_api_json.to_json))
    end

    it "returns 404 for the numeric id" do
      receipt = create_receipt
      get "/api/receipts/#{receipt.id}", headers: auth
      expect(response).to have_http_status(:not_found)
      expect(json["errors"]).to be_present
    end

    it "returns 404 for an unknown capture_id" do
      get "/api/receipts/#{SecureRandom.uuid}", headers: auth
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/receipts" do
    it "lists newest first in the contract's shape" do
      insert_receipts(3, created_at: ->(i) { i.hours.ago })
      get "/api/receipts", headers: auth

      expect(response).to have_http_status(:ok)
      expect(json.keys).to match_array(%w[receipts next_cursor])
      expect(json["receipts"].map { Time.iso8601(it["created_at"]) }).to eq(Receipt.order(created_at: :desc).map { it.created_at.change(usec: 0) })
      expect(json["next_cursor"]).to be_nil
    end

    it "filters by status" do
      insert_receipts(2)
      insert_receipts(1, parse_status: "needs_review")
      get "/api/receipts", params: { status: "needs_review" }, headers: auth
      expect(json["receipts"].map { it["parse_status"] }).to eq([ "needs_review" ])
    end

    it "clamps the limit to 1..200" do
      insert_receipts(201)

      get "/api/receipts", params: { limit: 0 }, headers: auth
      expect(json["receipts"].size).to eq(1)

      get "/api/receipts", params: { limit: 10_000 }, headers: auth
      expect(json["receipts"].size).to eq(200)
      expect(json["next_cursor"]).to be_present
    end

    it "pages with the cursor, returning every row once even when created_at is shared" do
      shared = Time.zone.parse("2026-10-24T15:42:12.123456Z")
      insert_receipts(5, created_at: shared)
      insert_receipts(2, created_at: shared - 1.minute)

      seen = []
      cursor = nil
      10.times do
        get "/api/receipts", params: { limit: 2, cursor: }.compact, headers: auth
        expect(response).to have_http_status(:ok)
        seen.concat(json["receipts"].map { it["capture_id"] })
        cursor = json["next_cursor"]
        break unless cursor
      end

      expect(seen).to eq(Receipt.order(created_at: :desc, id: :desc).pluck(:capture_id))
    end

    it "returns 422 for a malformed cursor" do
      [ "garbage!!", Base64.urlsafe_encode64("nope"), Base64.urlsafe_encode64("2026-10-24T00:00:00Z,abc") ].each do |cursor|
        get "/api/receipts", params: { cursor: }, headers: auth
        expect(response).to have_http_status(:unprocessable_content), cursor
      end
    end
  end

  describe "PATCH /api/receipts/:capture_id" do
    let(:update) { JSON.parse(contract_dir.join("update_receipt.request.json").read) }

    def patch_receipt(body)
      patch "/api/receipts/#{capture_id}", params: body.to_json, headers: auth.merge("Content-Type" => "application/json")
    end

    it "confirms even when the totals don't add up, replacing the items" do
      create_receipt
      patch_receipt(update)

      expect(response).to have_http_status(:ok)
      expect(json).to include("parse_status" => "confirmed", "merchant" => "Loblaws", "subtotal" => 2075, "total" => 2345)
      expect(json["confirmed_at"]).to be_present
      expect(json["items"]).to eq([ { "position" => 0, "description" => "BANANAS", "qty" => 1.234, "unit_price" => 79, "line_total" => 97 } ])
      expect(json["taxes"]).to eq([ { "label" => "HST", "rate" => 13.0, "amount" => 270 } ])
      expect(json["review_reasons"]).to include("items_sum_mismatch")
    end

    it "re-validates without confirm" do
      create_receipt
      patch_receipt(update.except("confirm"))
      expect(json).to include("parse_status" => "needs_review", "confirmed_at" => nil)
      expect(json["review_reasons"]).to eq([ "items_sum_mismatch" ])

      patch_receipt({ "subtotal" => 97, "tax" => 0, "taxes" => [], "total" => 97 })
      expect(json).to include("parse_status" => "parsed", "review_reasons" => [])
    end

    it "leaves fields that aren't sent" do
      create_receipt
      patch_receipt({ "merchant" => "Loblaws City Market" })
      expect(json).to include("merchant" => "Loblaws City Market", "total" => 843)
      expect(json["items"].size).to eq(2)
    end

    it "replaces the items and renumbers them in array order" do
      create_receipt
      patch_receipt({ "items" => [
        { "description" => "B", "qty" => 2, "unit_price" => 100, "line_total" => 200 },
        { "description" => "A", "qty" => 1, "unit_price" => -50, "line_total" => -50 }
      ] })
      expect(json["items"].map { [ it["position"], it["description"], it["line_total"] ] }).to eq([ [ 0, "B", 200 ], [ 1, "A", -50 ] ])

      patch_receipt({ "items" => [] })
      expect(json["items"]).to eq([])
    end

    it "returns 422 for an item without a line total, changing nothing" do
      create_receipt
      patch_receipt({ "merchant" => "X", "items" => [ { "description" => "B" } ] })
      expect(response).to have_http_status(:unprocessable_content)
      expect(Receipt.find_by!(capture_id:)).to have_attributes(merchant: "Loblaws", line_items: have_attributes(size: 2))
    end

    it "takes a confirmed receipt back to review when saved as a draft" do
      create_receipt
      patch_receipt(update)
      patch_receipt(update.except("confirm"))
      expect(json).to include("parse_status" => "needs_review", "confirmed_at" => nil)
    end

    it "returns 404 for the numeric id" do
      receipt = create_receipt
      patch "/api/receipts/#{receipt.id}", params: update.to_json, headers: auth.merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/receipts/:capture_id/images/:page" do
    it "sends the page image" do
      create_receipt(images: [ page_upload, page_upload("page.heic", "image/heic") ])

      get "/api/receipts/#{capture_id}/images/0", headers: auth
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("image/jpeg")
      expect(response.body.b).to eq(file_fixture("page.jpg").binread)

      get "/api/receipts/#{capture_id}/images/1", headers: auth
      expect(response.media_type).to eq("image/heic")
    end

    it "returns 404 past the last page, and for negative or non-numeric pages" do
      create_receipt
      %w[1 -1 abc 0x1].each do |page|
        get "/api/receipts/#{capture_id}/images/#{page}", headers: auth
        expect(response).to have_http_status(:not_found), page
      end
    end

    it "requires the token" do
      create_receipt
      get "/api/receipts/#{capture_id}/images/0"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/receipts/:capture_id/thumbnail" do
    it "sends the thumbnail, cached privately for a year" do
      create_receipt(thumbnail: fixture_file_upload("thumbnail.jpg", "image/jpeg"))
      get "/api/receipts/#{capture_id}/thumbnail", headers: auth

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("image/jpeg")
      expect(response.body.b).to eq(file_fixture("thumbnail.jpg").binread)
      expect(response.headers["Cache-Control"].split(", ")).to contain_exactly("private", "max-age=31536000", "immutable")
    end

    it "returns 404 when the receipt has no thumbnail" do
      create_receipt
      get "/api/receipts/#{capture_id}/thumbnail", headers: auth
      expect(response).to have_http_status(:not_found)
    end
  end
end
