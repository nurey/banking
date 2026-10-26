# rbs_inline: enabled
# frozen_string_literal: true

module ReceiptParser::Steps
  # The first row on page 0 with at least three letters that isn't a greeting,
  # an address, a phone number, a URL, a date, or a bare store number,
  # title-cased, with any store number and trailing punctuation dropped
  # ("LOBLAWS #1234" → "Loblaws", "Longos." → "Longos"). The search stops at the
  # transaction details (`Lane: 001`), so a receipt that only prints its address
  # has no merchant rather than a wrong one, unless that address is a known store.
  #
  # Known stores live in the encrypted credentials, so where the person shops
  # stays out of this public repo:
  #
  #   receipt_parser:
  #     known_addresses:
  #       "123 MAIN": Corner Grocer   # matches a header row starting "123 Main St…"
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
    # `Toronto, Ontario`, `MONTRÉAL, QC`, `TORONTO ON`
    CITY_PROVINCE = /\A[\p{L}\s.'-]+,?\s+(?:ON|ONT|ONTARIO|QC|QU[EÉ]BEC|BC|BRITISH\s+COLUMBIA|AB|ALBERTA|MB|MANITOBA|SK|SASKATCHEWAN|
      NS|NOVA\s+SCOTIA|NB|NEW\s+BRUNSWICK|PE|PEI|PRINCE\s+EDWARD\s+ISLAND|NL|NEWFOUNDLAND(?:\s+AND\s+LABRADOR)?|YT|YUKON|NT|NU|NUNAVUT)\.?\z/ix
    # `Lane: 001`, `Cashier: 156`, `Transaction: 10121907204` (but not `Store: 12`)
    DETAILS = /\A\s*(?!(?:STORE|MAGASIN)\b)\p{L}[\p{L}\s#.]*:\s*\d/i

    # @rbs known_addresses: Hash[String | Symbol, String]
    # @rbs return: void
    def initialize(known_addresses: Rails.application.credentials.dig(:receipt_parser, :known_addresses).to_h)
      @known_addresses = known_addresses.to_h do |address, name|
        [ /\A\s*#{address.to_s.split.map { Regexp.escape(it) }.join('\s+')}\b/i, name.to_s ]
      end
    end

    # @rbs ctx: ReceiptParser::Context
    # @rbs return: ReceiptParser::Context
    def call(ctx)
      header = ctx.rows.select { it.page.zero? && it.amount.nil? }
        .take_while { !it.text.match?(DETAILS) || it.text.match?(PHONE) }
      ctx.with(merchant: known_store(header) || header.lazy.filter_map { name(it.text) }.first)
    end

    private

    # @rbs rows: Array[ReceiptParser::Row]
    # @rbs return: String?
    def known_store(rows)
      rows.each do |row|
        @known_addresses.each { |address, name| return name if row.text.match?(address) }
      end
      nil
    end

    # @rbs text: String
    # @rbs return: String?
    def name(text)
      return if [ WELCOME, PHONE, URL, POSTAL_CODE, DATE_OR_TIME, CITY_PROVINCE ].any? { text.match?(it) }
      return if text.match?(/\A\s*\d+\w?\s+\S/) || (text.match?(/\d/) && text.match?(STREET))

      name = text.gsub(STORE_NUMBER, " ").squish.sub(/[\s.,:;]+\z/, "")
      return if name.scan(/\p{L}/).size < 3

      name.downcase.split.map(&:capitalize).join(" ")
    end
  end
end
