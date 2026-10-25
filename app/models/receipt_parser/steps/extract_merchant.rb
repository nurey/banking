# rbs_inline: enabled
# frozen_string_literal: true

module ReceiptParser::Steps
  # The first row on page 0 with at least three letters that isn't a greeting,
  # an address, a phone number, a URL, a date, or a bare store number,
  # title-cased, with any store number dropped ("LOBLAWS #1234" → "Loblaws").
  class ExtractMerchant
    READS = %i[rows].freeze
    WRITES = %i[merchant].freeze

    WELCOME = /\b(?:WELCOME|BIENVENUE)\b/i
    PHONE = /\(?\d{3}\)?[\s.-]?\d{3}[\s.-]\d{4}/
    URL = /www\.|https?:|\.(?:com|ca|net|org)\b/i
    POSTAL_CODE = /\b[ABCEGHJ-NPRSTVXY]\d[A-Z]\s?\d[A-Z]\d\b/i
    STREET = /\b(?:ST|STREET|AVE|AVENUE|RD|ROAD|BLVD|BOUL|DR|DRIVE|RUE|CHEMIN|HWY|WAY|CRES|PKWY|UNIT|SUITE)\b/i
    DATE_OR_TIME = /\d{1,4}[\/.-]\d{1,2}[\/.-]\d{2,4}|\d{1,2}:\d{2}/
    STORE_NUMBER = /(?:\bSTORE|\bMAGASIN|\bNO\.?)?\s*#\s*\d+|\b(?:STORE|MAGASIN)\s+\d+/i

    # @rbs ctx: ReceiptParser::Context
    # @rbs return: ReceiptParser::Context
    def call(ctx)
      name = ctx.rows.lazy.select { it.page.zero? && it.amount.nil? }.filter_map { name(it.text) }.first
      ctx.with(merchant: name)
    end

    private

    # @rbs text: String
    # @rbs return: String?
    def name(text)
      return if [ WELCOME, PHONE, URL, POSTAL_CODE, DATE_OR_TIME ].any? { text.match?(it) }
      return if text.match?(/\A\s*\d+\w?\s+\S/) || (text.match?(/\d/) && text.match?(STREET))

      name = text.gsub(STORE_NUMBER, " ").squish
      return if name.scan(/\p{L}/).size < 3

      name.downcase.split.map(&:capitalize).join(" ")
    end
  end
end
