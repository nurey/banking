# rbs_inline: enabled
# frozen_string_literal: true

module ReceiptParser
  # What the parser hands back: the output fields, its warnings, and the trace.
  # Receipt#apply_parse stores #as_json in receipts.parsed.
  class Result < Data.define(*Context::OUTPUTS, :warnings, :trace)
    # @rbs context: Context
    # @rbs return: Result
    def self.from(context)
      new(**context.to_h.slice(*members))
    end

    # @rbs return: Hash[String, untyped]
    def as_json(*)
      to_h.merge(
        items: items.map(&:to_h),
        taxes: taxes.map(&:to_h),
        purchased_on: purchased_on&.iso8601,
        purchased_at: purchased_at&.iso8601
      ).as_json
    end
  end
end
