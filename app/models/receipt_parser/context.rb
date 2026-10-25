# rbs_inline: enabled
# frozen_string_literal: true

module ReceiptParser
  # The one value threaded through the steps. A step returns ctx.with(...) and
  # never mutates anything.
  class Context < Data.define(
    :ocr_lines, :captured_at,
    :rows, :classified,
    :items, :subtotal, :taxes, :tax, :total, :card_last_four, :purchased_on, :purchased_at, :merchant,
    :warnings, :trace
  )
    INPUTS = %i[ocr_lines captured_at].freeze
    WORKING = %i[rows classified].freeze
    OUTPUTS = %i[items subtotal taxes tax total card_last_four purchased_on purchased_at merchant].freeze
    SHARED = %i[warnings trace].freeze

    # @rbs ocr_lines: Array[Hash[String, untyped]]
    # @rbs captured_at: Time?
    # @rbs return: Context
    def self.start(ocr_lines:, captured_at:)
      new(
        ocr_lines:, captured_at:,
        rows: [], classified: [],
        items: [], subtotal: nil, taxes: [], tax: nil, total: nil, card_last_four: nil,
        purchased_on: nil, purchased_at: nil, merchant: nil,
        warnings: [], trace: []
      )
    end
  end
end
