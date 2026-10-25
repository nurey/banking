# rbs_inline: enabled
# frozen_string_literal: true

module ReceiptParser::Steps
  # Item rows become items. A quantity row (`2 @ 3.99`, a weight) applies to the
  # adjacent item whose total it explains, preferring the one below; a quantity
  # printed on the item's own row wins. Without one, qty is 1. Discounts and
  # coupons are negative.
  class ExtractItems
    READS = %i[classified].freeze
    WRITES = %i[items subtotal].freeze

    DISCOUNT = /\b(?:COUPON|DISCOUNT|RABAIS|REMISE|SAVINGS|[EÉ]CONOMIE)\b/i
    SKU = /\A(\d{4,})\s+/
    # A UPC/EAN printed after the name (Walmart: `BKF SFTCLNSR 071618116370`)
    BARCODE = /\s+(\d{8,14})\z/

    # @rbs ctx: ReceiptParser::Context
    # @rbs return: ReceiptParser::Context
    def call(ctx)
      rows = ctx.classified
      quantities = assign_quantities(rows)
      items = rows.each_with_index.filter_map do |row, index|
        build_item(rows, index, row.quantity || quantities[index]) if row.item?
      end
      ctx.with(items:, subtotal: rows.find(&:subtotal?)&.amount)
    end

    private

    # Maps an item row's index to the quantity row that belongs to it.
    #
    # @rbs rows: Array[ReceiptParser::ClassifiedRow]
    # @rbs return: Hash[Integer, ReceiptParser::Quantity]
    def assign_quantities(rows)
      rows.each_with_index.each_with_object({}) do |(row, index), assigned|
        next unless row.quantity?

        below = index + 1 if rows[index + 1]&.item? && !assigned.key?(index + 1)
        above = index - 1 if index.positive? && rows[index - 1].item? && !assigned.key?(index - 1)
        target =
          if below && explains?(row.quantity, rows[below].amount) then below
          elsif above && explains?(row.quantity, rows[above].amount) then above
          else below || above
          end
        assigned[target] = row.quantity if target
      end
    end

    # @rbs quantity: ReceiptParser::Quantity
    # @rbs amount: Integer
    # @rbs return: bool
    def explains?(quantity, amount)
      quantity.qty.nil? || (quantity.qty * quantity.unit_price - amount).abs <= 1
    end

    # @rbs rows: Array[ReceiptParser::ClassifiedRow]
    # @rbs index: Integer
    # @rbs quantity: ReceiptParser::Quantity?
    # @rbs return: ReceiptParser::Item
    def build_item(rows, index, quantity)
      row = rows[index]
      sku, description = describe(row.text)
      description = description_above(rows, index) if description.empty?

      line_total = row.amount
      line_total = -line_total if line_total.positive? && row.text.match?(DISCOUNT)

      qty, unit_price =
        if quantity&.qty then [ quantity.qty, quantity.unit_price ]
        elsif quantity
          count = [ (line_total / quantity.unit_price).round, 1 ].max
          [ count, (BigDecimal(line_total) / count).round.to_i ]
        else [ 1, line_total ]
        end

      ReceiptParser::Item.new(description:, qty:, unit_price:, line_total:, sku:)
    end

    # The text left of the row's amount, without a printed quantity, a leading SKU
    # or a trailing barcode.
    #
    # @rbs text: String
    # @rbs return: [String?, String]
    def describe(text)
      last = ReceiptParser::Money.matches(text).last
      text = last ? text[0...last.begin(0)] : text
      text = text.sub(ClassifyRows::QUANTITY, "").sub(ClassifyRows::MULTI_BUY, "")
      sku = text[SKU, 1]
      text = text.sub(SKU, "") if sku
      barcode = text.rstrip[BARCODE, 1]
      text = text.rstrip.sub(BARCODE, "") if barcode
      [ sku || barcode, text.squish ]
    end

    # When the price sits on its own row, the description is the row above it.
    #
    # @rbs rows: Array[ReceiptParser::ClassifiedRow]
    # @rbs index: Integer
    # @rbs return: String
    def description_above(rows, index)
      rows[0...index].reverse.take(2).reject(&:quantity?).find { it.other? && it.amount.nil? }&.text.to_s.squish
    end
  end
end
