# rbs_inline: enabled
# frozen_string_literal: true

module ReceiptParser
  # The lines that share one printed row, left to right. `money` holds the row's
  # money tokens in cents, left to right; NormalizeTokens fills it.
  Row = Data.define(:page, :y, :height, :cells, :money) do
    # @rbs return: String
    def text = cells.map(&:text).join(" ")

    # The right-most money token.
    #
    # @rbs return: Integer?
    def amount = money.last
  end
end
