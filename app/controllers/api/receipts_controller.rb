# rbs_inline: enabled
# frozen_string_literal: true

module Api
  # The receipt-scanner app's API: upload a capture, read receipts back, and
  # correct or confirm the parsed fields. See the contract in receipt-scanner.
  class ReceiptsController < BaseController
    MAX_OCR_LINES = 5_000
    MAX_RAW_TEXT = 200.kilobytes
    DEFAULT_LIMIT = 50
    MAX_LIMIT = 200

    # @rbs return: void
    def index
      scope = Receipt.order(created_at: :desc, id: :desc)
        .includes(:line_items, images_attachments: :blob, thumbnail_attachment: :blob)
      scope = scope.where(parse_status: params[:status]) if params[:status].present?
      if params[:cursor].present?
        created_at, id = decode_cursor(params[:cursor])
        return render_errors("cursor is malformed", status: :unprocessable_content) unless created_at

        scope = scope.where("(receipts.created_at, receipts.id) < (?, ?)", created_at, id)
      end

      limit = params.fetch(:limit, DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)
      receipts = scope.limit(limit + 1).to_a
      next_cursor = encode_cursor(receipts[limit - 1]) if receipts.size > limit
      render json: { receipts: receipts.first(limit).map(&:as_api_json), next_cursor: }
    end

    # @rbs return: void
    def show
      render json: find_receipt.as_api_json
    end

    # @rbs return: void
    def create
      capture = parse_capture
      return render_errors("receipt must be a JSON object", status: :unprocessable_content) unless capture

      existing = Receipt.find_by(capture_id: capture["capture_id"])
      return render json: existing.as_api_json, status: :ok if existing&.files_stored?

      existing&.destroy! # its files were never written: store the capture again

      if (too_large = size_error(capture))
        return render_errors(too_large, status: :content_too_large)
      end

      images = params[:images]
      unless images.is_a?(Array) && images.all?(ActionDispatch::Http::UploadedFile)
        return render_errors("images must be one or more file parts", status: :unprocessable_content)
      end

      thumbnail = params[:thumbnail]
      if thumbnail && !thumbnail.is_a?(ActionDispatch::Http::UploadedFile)
        return render_errors("thumbnail must be a file part", status: :unprocessable_content)
      end

      if (invalid = shape_errors(capture, page_count: images.size)).any?
        return render_errors(invalid, status: :unprocessable_content)
      end

      receipt = Receipt.new(**capture_attributes(capture), parse_status: "failed", images:)
      receipt.thumbnail = thumbnail if thumbnail
      store(receipt)

      parse(receipt)
      render json: receipt.as_api_json, status: :created
    rescue ActiveRecord::RecordInvalid => e
      return render_existing(capture) if e.record.errors.of_kind?(:capture_id, :taken)

      render_errors e.record.errors.full_messages, status: :unprocessable_content
    rescue ActiveRecord::RecordNotUnique
      render_existing(capture) # two retries of the same capture racing
    end

    # Every field is optional. `items` replaces the whole list. `confirm: true`
    # confirms even if the totals don't add up: the person has the final say.
    #
    # @rbs return: void
    def update
      receipt = find_receipt
      changes = update_params

      Receipt.transaction do
        receipt.assign_attributes(changes.slice(:merchant, :purchased_on, :purchased_at, :subtotal, :tax, :total))
        receipt.taxes = changes[:taxes].map(&:to_h) if changes.key?(:taxes)
        receipt.replace_line_items(changes[:items].map { it.to_h.symbolize_keys }) if changes.key?(:items)

        if ActiveModel::Type::Boolean.new.cast(changes[:confirm])
          receipt.update!(parse_status: "confirmed", confirmed_at: Time.current, review_reasons: ReceiptValidator.for_receipt(receipt))
        else
          receipt.confirmed_at = nil
          receipt.save!
          receipt.revalidate!
        end
      end

      render json: receipt.reload.as_api_json
    rescue ActiveRecord::RecordInvalid => e
      render_errors e.record.errors.full_messages, status: :unprocessable_content
    end

    private

    # @rbs return: Hash[String, untyped]?
    def parse_capture
      part = params[:receipt]
      part = part.read if part.respond_to?(:read)
      document = JSON.parse(part.to_s)
      document if document.is_a?(Hash)
    rescue JSON::ParserError
      nil
    end

    # @rbs capture: Hash[String, untyped]
    # @rbs return: String?
    def size_error(capture)
      lines = capture["ocr_lines"]
      return "ocr_lines has more than #{MAX_OCR_LINES} lines" if lines.is_a?(Array) && lines.size > MAX_OCR_LINES

      "raw_text is over 200 KB" if capture["raw_text"].to_s.bytesize > MAX_RAW_TEXT
    end

    # @rbs capture: Hash[String, untyped]
    # @rbs page_count: Integer
    # @rbs return: Array[String]
    def shape_errors(capture, page_count:)
      return [ "raw_text must be a string" ] unless capture["raw_text"].is_a?(String)

      lines = capture["ocr_lines"]
      return [ "ocr_lines must be an array" ] unless lines.is_a?(Array)

      lines.each_with_index.filter_map do |line, index|
        next "ocr_lines[#{index}] must be an object" unless line.is_a?(Hash)

        page = line["page"]
        if !page.is_a?(Integer) || !page.between?(0, page_count - 1)
          "ocr_lines[#{index}].page must be an image index from 0 to #{page_count - 1}"
        elsif !line["text"].is_a?(String)
          "ocr_lines[#{index}].text must be a string"
        elsif !%w[x y w h confidence].all? { line[it].is_a?(Numeric) }
          "ocr_lines[#{index}] must have numeric x, y, w, h, and confidence"
        end
      end.first(10)
    end

    # JSON.parse returns a plain Hash that strong params don't filter, so copy
    # an explicit list: a capture must never set parse_status, confirmed_at, or parsed.
    #
    # @rbs capture: Hash[String, untyped]
    # @rbs return: Hash[Symbol, untyped]
    def capture_attributes(capture)
      {
        capture_id: capture["capture_id"],
        captured_at: capture["captured_at"],
        currency: capture["currency"].presence || "CAD",
        raw_text: capture["raw_text"],
        ocr_lines: capture["ocr_lines"],
        metadata: capture.slice("ocr", "device")
      }
    end

    # Active Storage writes the files after the row commits. If that fails, the
    # row goes too, so the app's retry stores the capture again instead of
    # getting back a receipt whose images don't exist.
    #
    # @rbs receipt: Receipt
    # @rbs return: void
    def store(receipt)
      receipt.save!
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      raise
    rescue StandardError
      receipt.destroy if receipt.persisted?
      raise
    end

    # Parsing never rejects the upload: on any error the receipt stays `failed`
    # with its capture and images stored.
    #
    # @rbs receipt: Receipt
    # @rbs return: void
    def parse(receipt)
      receipt.apply_parse(ReceiptParser.call(ocr_lines: receipt.ocr_lines, captured_at: receipt.captured_at))
    rescue StandardError => e
      Rails.logger.error("Receipt #{receipt.capture_id} parse failed: #{e.class}: #{e.message}")
      receipt.record_parse_failure(e)
    end

    # @rbs capture: Hash[String, untyped]
    # @rbs return: void
    def render_existing(capture)
      render json: Receipt.find_by!(capture_id: capture["capture_id"]).as_api_json, status: :ok
    end

    # @rbs return: ActionController::Parameters
    def update_params
      params.permit(
        :merchant, :purchased_on, :purchased_at, :subtotal, :tax, :total, :confirm,
        taxes: %i[label rate amount], items: %i[description qty unit_price line_total sku]
      )
    end

    # The last row's (created_at, id), so rows sharing a created_at aren't skipped.
    # Opaque to the app.
    #
    # @rbs receipt: Receipt
    # @rbs return: String
    def encode_cursor(receipt)
      Base64.urlsafe_encode64("#{receipt.created_at.utc.iso8601(6)},#{receipt.id}", padding: false)
    end

    # @rbs cursor: String
    # @rbs return: [Time, Integer]?
    def decode_cursor(cursor)
      created_at, id = Base64.urlsafe_decode64(cursor).split(",", 2)
      [ Time.iso8601(created_at.to_s), Integer(id.to_s, 10) ]
    rescue ArgumentError
      nil
    end
  end
end
