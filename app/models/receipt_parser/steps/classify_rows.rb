# rbs_inline: enabled
# frozen_string_literal: true

module ReceiptParser::Steps
  # Labels each row by keyword (English and French): subtotal, tax, total
  # candidate, payment, a quantity-only row, an item, or other. Items are the
  # rows with an amount above the subtotal (or, without one, above the first
  # tax, total, or payment row). Also finds the card's last four digits.
  class ClassifyRows
    READS = %i[rows].freeze
    WRITES = %i[classified card_last_four].freeze

    SUBTOTAL = /\b(?:SUB\s*-?\s*TOTAL|SOUS[\s-]*TOTAL)\b/i
    TAX = /\b(?:HST|TVH|GST|TPS|PST|QST|TVQ|TAX|TAXE|TAXES)\b/i
    TOTAL = /\b(?:MONTANT\s+TOTAL|TOTAL|BALANCE\s+DUE|AMOUNT\s+DUE)\b/i
    # "TOTAL SAVINGS", "TOTAL NUMBER OF ITEMS SOLD", "TOTAL TAX": not the amount paid.
    NOT_TOTAL = /\b(?:SAVINGS?|SAVED|DISCOUNTS?|ITEMS?|NUMBER|POINTS|ARTICLES?|[EÉ]CONOMIES?)\b/i
    PAYMENT = /\b(?:VISA|MASTERCARD|MC|AMEX|DEBIT|INTERAC|CASH|CHANGE|TENDER(?:ED)?|APPROVED|AUTH)\b/i
    CARD = /(?:\*{4,}|X{4,})\s*(\d{4})(?!\d)/i
    # Vision collapses long runs of * or X ("**4242", "XXX1234"), so on a
    # payment row a shorter mask counts too.
    PAYMENT_CARD = /(?:\*+|X{2,}|\#+)\s*(\d{4})(?!\d)/i
    RATE = /(?<!\d)(\d{1,2}(?:[.,]\d{1,3})?)\s*%/
    # `2 @ 3.99`, `2 x 3.99`, `1.234 kg @ $0.79/kg`
    QUANTITY = /(?<![\d.,])(?<qty>\d+(?:[.,]\d+)?)\s*(?:kg|lbs?)?\s*[@xX×]\s*\$?(?<unit>\d+[.,]\d{2})(?!\d)/i
    # `3/$5.00`: three for $5.00
    MULTI_BUY = /(?<![\d.,])(?<count>\d+)\s*\/\s*\$?(?<price>\d+[.,]\d{2})(?!\d)/

    # @rbs ctx: ReceiptParser::Context
    # @rbs return: ReceiptParser::Context
    def call(ctx)
      keywords = ctx.rows.map { keyword_kind(it.text) }
      item_region_end = keywords.index(:subtotal) ||
        keywords.index { %i[tax total payment].include?(it) } ||
        ctx.rows.size

      classified = ctx.rows.each_with_index.map do |row, index|
        kind = keywords[index]
        quantity = quantity(row.text)
        kind =
          if kind == :not_total || (kind.nil? && index >= item_region_end) then :other
          elsif kind then kind
          elsif quantity && row.money.size == 1 then :quantity
          elsif row.amount then :item
          else :other
          end
        rate = kind == :tax ? RATE.match(row.text)&.then { it[1].tr(",", ".").to_f } : nil
        ReceiptParser::ClassifiedRow.new(row:, kind:, rate:, quantity:)
      end

      card_last_four = ctx.rows.lazy.filter_map { CARD.match(it.text)&.[](1) }.first ||
        classified.lazy.select(&:payment?).filter_map { PAYMENT_CARD.match(it.text)&.[](1) }.first
      ctx.with(classified:, card_last_four:)
    end

    private

    # @rbs text: String
    # @rbs return: Symbol?
    def keyword_kind(text)
      if text.match?(SUBTOTAL) then :subtotal
      elsif text.match?(TAX) && text.match?(TOTAL) then :not_total
      elsif text.match?(TAX) then :tax
      elsif text.match?(TOTAL) then text.match?(NOT_TOTAL) ? :not_total : :total
      elsif text.match?(PAYMENT) then :payment
      end
    end

    # @rbs text: String
    # @rbs return: ReceiptParser::Quantity?
    def quantity(text)
      if (match = QUANTITY.match(text))
        qty = match[:qty].tr(",", ".")
        ReceiptParser::Quantity.new(qty: qty.include?(".") ? BigDecimal(qty) : qty.to_i, unit_price: cents(match[:unit]))
      elsif (match = MULTI_BUY.match(text)) && match[:count].to_i.positive?
        ReceiptParser::Quantity.new(qty: nil, unit_price: BigDecimal(cents(match[:price])) / match[:count].to_i)
      end
    end

    # @rbs amount: String
    # @rbs return: Integer
    def cents(amount) = (BigDecimal(amount.tr(",", ".")) * 100).round.to_i
  end
end
