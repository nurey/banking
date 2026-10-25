# rbs_inline: enabled
# frozen_string_literal: true

module ReceiptParser
  # Money in integer cents; line_total is negative for discounts and coupons.
  Item = Data.define(:description, :qty, :unit_price, :line_total, :sku)
end
