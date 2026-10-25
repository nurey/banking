# rbs_inline: enabled
# frozen_string_literal: true

module ReceiptParser::Steps
  # Of the total candidates, prefer the one that equals the payment amount.
  # Otherwise take the last one before the payment rows.
  class PickTotal
    READS = %i[classified].freeze
    WRITES = %i[total].freeze

    # @rbs ctx: ReceiptParser::Context
    # @rbs return: ReceiptParser::Context
    def call(ctx)
      rows = ctx.classified
      first_payment = rows.index { it.payment? && it.amount }
      candidates = rows.each_with_index.select { |row, _| row.total? && row.amount }
      paid = rows[first_payment].amount if first_payment

      row, = candidates.find { |candidate, _| paid && candidate.amount == paid } ||
        candidates.select { |_, index| first_payment.nil? || index < first_payment }.last ||
        candidates.last
      return ctx.with(warnings: ctx.warnings + [ :no_total_candidate ]) unless row

      ctx.with(total: row.amount)
    end
  end
end
