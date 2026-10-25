# rbs_inline: enabled
# frozen_string_literal: true

module ReceiptParser
  # One printed tax line. `rate` is the printed percentage, or nil.
  Tax = Data.define(:label, :rate, :amount)
end
