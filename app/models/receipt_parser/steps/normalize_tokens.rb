# rbs_inline: enabled
# frozen_string_literal: true

module ReceiptParser::Steps
  # Language correction is off on the phone (it "fixes" prices), so Vision
  # leaves the usual letter/digit mix-ups in numbers: 12.O0, l.99, 3.4S, B.99.
  # Fix them inside number-like tokens only, then find each row's money tokens.
  class NormalizeTokens
    READS = %i[rows].freeze
    WRITES = %i[rows].freeze

    LOOKALIKES = [ "OoIl|SB", "0011158" ].freeze
    NUMBER_LIKE = /\A[-+$]?\d+(?:[.,]\d+)*[-%]?\z/

    # @rbs ctx: ReceiptParser::Context
    # @rbs return: ReceiptParser::Context
    def call(ctx)
      rows = ctx.rows.map do |row|
        cells = row.cells.map { it.with(text: normalize(it.text)) }
        row.with(cells:, money: ReceiptParser::Money.scan(cells.map(&:text).join(" ")))
      end
      ctx.with(rows:)
    end

    private

    # @rbs text: String
    # @rbs return: String
    def normalize(text)
      text.gsub(/\S+/) do |token|
        next token unless token.match?(/\d/)

        fixed = token.tr(*LOOKALIKES)
        fixed.match?(NUMBER_LIKE) ? fixed : token
      end
    end
  end
end
