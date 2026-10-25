# rbs_inline: enabled
# frozen_string_literal: true

module ReceiptParser::Steps
  # One Tax per tax row with an amount; `tax` is their sum, or nil without any.
  class ExtractTaxes
    READS = %i[classified].freeze
    WRITES = %i[taxes tax].freeze

    LABEL = /\b(HST|TVH|GST|TPS|PST|QST|TVQ)\b/i

    # @rbs ctx: ReceiptParser::Context
    # @rbs return: ReceiptParser::Context
    def call(ctx)
      taxes = ctx.classified.select { it.tax? && it.amount }.map do |row|
        label = row.text[LABEL, 1]&.upcase || "TAX"
        ReceiptParser::Tax.new(label:, rate: row.rate, amount: row.amount)
      end
      ctx.with(taxes:, tax: (taxes.sum(&:amount) if taxes.any?))
    end
  end
end
