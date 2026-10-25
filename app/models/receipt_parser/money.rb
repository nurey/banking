# rbs_inline: enabled
# frozen_string_literal: true

module ReceiptParser
  # Money tokens in OCR text: an optional `$`, a dot or comma decimal mark, an
  # optional thousands separator, and a leading or trailing minus (Costco prints
  # discounts as `5.00-`). Percentages, weights with three decimals, and dotted
  # dates don't count.
  module Money
    PATTERN = /
      (?<![\d.,])
      (?<neg>-)?\$?
      (?<int>\d{1,3}(?:,\d{3})+|\d{1,5})[.,](?<dec>\d{2})
      (?<tneg>-)?
      (?![\d%]|[.,]\d)
    /x

    # @rbs text: String
    # @rbs return: Array[MatchData]
    def self.matches(text)
      text.to_enum(:scan, PATTERN).map { Regexp.last_match }
    end

    # Every money token in the text, left to right, in cents.
    #
    # @rbs text: String
    # @rbs return: Array[Integer]
    def self.scan(text)
      matches(text).map { cents(it) }
    end

    # @rbs match: MatchData
    # @rbs return: Integer
    def self.cents(match)
      value = match[:int].delete(",").to_i * 100 + match[:dec].to_i
      match[:neg] || match[:tneg] ? -value : value
    end
  end
end
