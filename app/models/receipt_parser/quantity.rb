# rbs_inline: enabled
# frozen_string_literal: true

module ReceiptParser
  # A printed quantity: `2 @ 3.99` (qty 2, unit 399), `1.234 kg @ $0.79/kg`
  # (qty 1.234, unit 79), or a multi-buy `3/$5.00` (qty unknown, unit 500/3).
  Quantity = Data.define(:qty, :unit_price)
end
