# rbs_inline: enabled
# frozen_string_literal: true

# A paper receipt scanned by the receipt-scanner iPhone app. The phone uploads the
# page images and its OCR output; ReceiptParser fills in the rest.
class Receipt < ApplicationRecord
  # Receipts print local wall-clock times with no offset.
  TIME_ZONE = "America/Toronto"

  MAX_PAGES = 8
  MAX_PAGE_SIZE = 8.megabytes
  MAX_THUMBNAIL_SIZE = 256.kilobytes
  PAGE_TYPES = %w[image/jpeg image/heic].freeze
  HEIC_BRANDS = %w[heic heix mif1].freeze

  has_many :line_items, -> { order(:position) }, class_name: "ReceiptLineItem", dependent: :destroy

  # Page n is images.order(:id)[n]: upload order, which ocr_lines[].page indexes.
  has_many_attached :images
  has_one_attached :thumbnail

  enum :parse_status, %w[parsed needs_review confirmed failed].index_by(&:itself), validate: true

  validates :capture_id, presence: true, uniqueness: true
  validates :raw_text, :ocr_lines, presence: true
  validate :images_acceptable
  validate :thumbnail_acceptable

  # URLs and lookups use the device's capture_id, never the internal id.
  #
  # @rbs return: String?
  def to_param = capture_id

  # @rbs return: Array[ActiveStorage::Attachment]
  def pages
    images_attachments.sort_by(&:id)
  end

  # Writes the parser's fields and items, keeps its untouched output in
  # `parsed`, and sets the status from ReceiptValidator. A confirmed receipt is
  # a person's final answer, so it's left alone.
  #
  # @rbs result: ReceiptParser::Result
  # @rbs return: void
  def apply_parse(result)
    return if confirmed?

    reasons = ReceiptValidator.for_result(result, confidences: ocr_lines.map { it["confidence"].to_f })
    transaction do
      replace_line_items(result.items.map(&:to_h))
      update!(
        **result.to_h.slice(:merchant, :purchased_on, :purchased_at, :subtotal, :tax, :total, :card_last_four),
        taxes: result.taxes.map(&:to_h),
        parsed: result.as_json,
        parser_version: ReceiptParser::VERSION,
        review_reasons: reasons,
        parse_status: reasons.empty? ? "parsed" : "needs_review"
      )
    end
  end

  # The capture and images stay; only the extracted fields are missing.
  #
  # @rbs error: StandardError
  # @rbs return: void
  def record_parse_failure(error)
    failed_step = error.step.name.demodulize if error.is_a?(ReceiptParser::StepError)
    update!(
      parse_status: "failed",
      parser_version: ReceiptParser::VERSION,
      parsed: { "error" => error.message, "failed_step" => failed_step }.compact
    )
  end

  # Re-checks the current, possibly hand-edited, values.
  #
  # @rbs return: void
  def revalidate!
    reasons = ReceiptValidator.for_receipt(self)
    update!(review_reasons: reasons, parse_status: reasons.empty? ? "parsed" : "needs_review")
  end

  # Replaces every line item, numbering them in array order.
  #
  # @rbs items: Array[Hash[Symbol, untyped]]
  # @rbs return: void
  def replace_line_items(items)
    line_items.delete_all
    items.each_with_index do |item, position|
      line_items.create!(**item.slice(:description, :qty, :unit_price, :line_total, :sku), position:)
    end
    line_items.reset
  end

  # @rbs return: Hash[Symbol, untyped]
  def as_api_json
    {
      id:,
      capture_id:,
      parse_status:,
      review_reasons:,
      merchant:,
      purchased_on: purchased_on&.iso8601,
      purchased_at: purchased_at&.in_time_zone(TIME_ZONE)&.iso8601,
      currency:,
      subtotal:,
      tax:,
      taxes:,
      total:,
      card_last_four:,
      items: line_items.map(&:as_api_json),
      images: pages.each_with_index.map do |image, page|
        { page:, url: "/api/receipts/#{capture_id}/images/#{page}", byte_size: image.blob.byte_size }
      end,
      thumbnail: (
        { url: "/api/receipts/#{capture_id}/thumbnail", byte_size: thumbnail.blob.byte_size } if thumbnail.attached?
      ),
      parser_version:,
      confirmed_at: confirmed_at&.utc&.iso8601,
      created_at: created_at&.utc&.iso8601,
      updated_at: updated_at&.utc&.iso8601
    }
  end

  private

  # Active Storage's content type isn't enough on its own: Marcel checks the bytes
  # first, but when they match nothing it falls back to the filename and the
  # declared type, so arbitrary bytes named x.jpg would pass as image/jpeg and
  # later be served inline as one. New uploads also have their leading bytes checked.
  def images_acceptable
    unless images.size.between?(1, MAX_PAGES)
      errors.add(:images, "must have between 1 and #{MAX_PAGES} pages")
    end

    images.each_with_index do |image, page|
      blob = image.blob
      errors.add(:images, "page #{page} is over 8 MB") if blob.byte_size > MAX_PAGE_SIZE
      errors.add(:images, "page #{page} must be a JPEG or HEIC image") unless PAGE_TYPES.include?(blob.content_type)
    end

    new_attachables(:images).each do |attachable|
      head = leading_bytes(attachable)
      errors.add(:images, "must be uploaded files") and next if head.nil?
      errors.add(:images, "contain a file that isn't a JPEG or HEIC image") unless jpeg?(head) || heic?(head)
    end
  end

  def thumbnail_acceptable
    return unless thumbnail.attached?

    blob = thumbnail.blob
    errors.add(:thumbnail, "is over 256 KB") if blob.byte_size > MAX_THUMBNAIL_SIZE
    errors.add(:thumbnail, "must be a JPEG image") unless blob.content_type == "image/jpeg"

    new_attachables(:thumbnail).each do |attachable|
      head = leading_bytes(attachable)
      errors.add(:thumbnail, "must be a JPEG image") unless head && jpeg?(head)
    end
  end

  # The files assigned since the last save, before Active Storage uploads them.
  #
  # @rbs name: Symbol
  # @rbs return: Array[untyped]
  def new_attachables(name)
    change = attachment_changes[name.to_s]
    case change
    when ActiveStorage::Attached::Changes::CreateMany then change.attachables
    when ActiveStorage::Attached::Changes::CreateOne then [ change.attachable ]
    else []
    end
  end

  # @rbs attachable: untyped
  # @rbs return: String?
  def leading_bytes(attachable)
    io = attachable.is_a?(Hash) ? attachable[:io] : attachable
    return unless io.respond_to?(:read) && io.respond_to?(:rewind)

    io.rewind
    io.read(12).to_s.b.tap { io.rewind }
  end

  # @rbs head: String
  # @rbs return: bool
  def jpeg?(head) = head.start_with?("\xFF\xD8\xFF".b)

  # An ISO-BMFF ftyp box: bytes 4..7 are "ftyp" and 8..11 the major brand.
  #
  # @rbs head: String
  # @rbs return: bool
  def heic?(head) = head[4, 4] == "ftyp" && HEIC_BRANDS.include?(head[8, 4])
end

# == Schema Information
#
# Table name: receipts
#
#  id             :bigint           not null, primary key
#  captured_at    :datetime
#  card_last_four :text
#  confirmed_at   :datetime
#  currency       :text             default("CAD"), not null
#  merchant       :text
#  metadata       :jsonb            not null
#  ocr_lines      :jsonb            not null
#  parse_status   :text             not null
#  parsed         :jsonb            not null
#  parser_version :integer
#  purchased_at   :datetime
#  purchased_on   :date
#  raw_text       :text             not null
#  review_reasons :text             default([]), not null, is an Array
#  subtotal       :integer
#  tax            :integer
#  taxes          :jsonb            not null
#  total          :integer
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  capture_id     :uuid             not null
#
# Indexes
#
#  index_receipts_on_capture_id         (capture_id) UNIQUE
#  index_receipts_on_created_at_and_id  (created_at,id)
#  index_receipts_on_parse_status       (parse_status)
#  index_receipts_on_purchased_on       (purchased_on)
#
