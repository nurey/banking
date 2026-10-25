# rbs_inline: enabled
# frozen_string_literal: true

module ReceiptParser::Steps
  # Finds the purchase date, and the time when one is printed next to it.
  # Numeric dates can be read several ways (24/10 or 10/24); the reading not
  # after the capture and closest to it wins, with an :ambiguous_date warning.
  # Dates after the capture (return-by dates) lose to ones before it. Times
  # are America/Toronto unless an offset is printed.
  class ExtractDate
    READS = %i[rows captured_at].freeze
    WRITES = %i[purchased_on purchased_at].freeze

    MONTHS = {
      1 => %w[jan january janv janvier], 2 => %w[feb february fev fév fevr févr fevrier février],
      3 => %w[mar march mars], 4 => %w[apr april avr avril], 5 => %w[may mai], 6 => %w[jun june juin],
      7 => %w[jul july juil juillet], 8 => %w[aug august aout août], 9 => %w[sep sept september septembre],
      10 => %w[oct october octobre], 11 => %w[nov november novembre], 12 => %w[dec december déc decembre décembre]
    }.flat_map { |number, names| names.map { [ it, number ] } }.to_h.freeze

    ISO = /(?<!\d)(?<y>\d{4})[-\/.](?<m>\d{1,2})[-\/.](?<d>\d{1,2})(?!\d)/
    NUMERIC = /(?<![\d\/.-])(?<a>\d{1,2})[-\/.](?<b>\d{1,2})[-\/.](?<c>\d{4}|\d{2})(?![\d\/.-])/
    DAY_MONTH_YEAR = /(?<!\d)(?<d>\d{1,2})[\s-]*(?<mon>\p{L}{3,9})\.?[\s,-]*(?<y>\d{4})(?!\d)/
    MONTH_DAY_YEAR = /(?<!\p{L})(?<mon>\p{L}{3,9})\.?\s*(?<d>\d{1,2})(?:st|nd|rd|th)?,?\s+(?<y>\d{4})(?!\d)/i
    TIME = /
      (?<![\d:])(?<h>\d{1,2}):(?<min>\d{2})(?::(?<s>\d{2}))?(?!\d)
      (?:\s*(?<ampm>[AaPp])\.?\s?[Mm]\.?)?
      (?:\s*(?<off>Z|[+-]\d{2}:?\d{2}))?
    /x

    # @rbs ctx: ReceiptParser::Context
    # @rbs return: ReceiptParser::Context
    def call(ctx)
      captured_on = ctx.captured_at&.in_time_zone(Receipt::TIME_ZONE)&.to_date
      candidates = ctx.rows.each_with_index.flat_map do |row, index|
        readings(row.text).map { [ index, it ] }
      end
      return ctx if candidates.empty?

      index, dates = choose(candidates, captured_on)
      date = captured_on ? dates.select { it <= captured_on + 1 }.max || dates.min : dates.first
      warnings = dates.size > 1 ? ctx.warnings + [ :ambiguous_date ] : ctx.warnings

      ctx.with(purchased_on: date, purchased_at: time_near(ctx.rows, index, date), warnings:)
    end

    private

    # The first date in reading order that can be on or before the capture
    # (allowing a day for time zones), or the first date of all.
    #
    # @rbs candidates: Array[[Integer, Array[Date]]]
    # @rbs captured_on: Date?
    # @rbs return: [Integer, Array[Date]]
    def choose(candidates, captured_on)
      return candidates.first unless captured_on

      candidates.find { |_, dates| dates.any? { it <= captured_on + 1 } } || candidates.first
    end

    # Every valid reading of each date printed in the text, one array per date.
    #
    # @rbs text: String
    # @rbs return: Array[Array[Date]]
    def readings(text)
      found = []
      text.scan(ISO) { found << [ date(*Regexp.last_match.values_at(:y, :m, :d)) ] }
      text.scan(NUMERIC) do
        a, b, c = Regexp.last_match.values_at(:a, :b, :c)
        found << [ date(c, b, a), date(c, a, b), (date(a, b, c) if c.size == 2) ].compact.uniq
      end
      text.scan(DAY_MONTH_YEAR) do
        match = Regexp.last_match
        found << [ date(match[:y], month(match[:mon]), match[:d]) ]
      end
      text.scan(MONTH_DAY_YEAR) do
        match = Regexp.last_match
        found << [ date(match[:y], month(match[:mon]), match[:d]) ]
      end
      found.map(&:compact).reject(&:empty?)
    end

    # @rbs name: String
    # @rbs return: Integer?
    def month(name) = MONTHS[name.downcase]

    # @rbs year: String | Integer
    # @rbs month: String | Integer | nil
    # @rbs day: String | Integer
    # @rbs return: Date?
    def date(year, month, day)
      return unless month

      year = year.to_i
      year += 2000 if year < 100
      return unless year.between?(2000, 2099) && Date.valid_date?(year, month.to_i, day.to_i)

      Date.new(year, month.to_i, day.to_i)
    end

    # A time on the date's row, or failing that the row after or before it.
    #
    # @rbs rows: Array[ReceiptParser::Row]
    # @rbs index: Integer
    # @rbs date: Date
    # @rbs return: ActiveSupport::TimeWithZone | Time | nil
    def time_near(rows, index, date)
      [ index, index + 1, index - 1 ].each do |i|
        next if i.negative? || rows[i].nil?

        rows[i].text.scan(TIME) do
          time = build_time(date, Regexp.last_match)
          return time if time
        end
      end
      nil
    end

    # @rbs date: Date
    # @rbs match: MatchData
    # @rbs return: ActiveSupport::TimeWithZone | Time | nil
    def build_time(date, match)
      hour, min, sec = match[:h].to_i, match[:min].to_i, match[:s].to_i
      if match[:ampm]
        return unless hour.between?(1, 12)

        hour = (hour % 12) + (match[:ampm].casecmp?("p") ? 12 : 0)
      end
      return unless hour < 24 && min < 60 && sec < 60

      if match[:off]
        offset = match[:off] == "Z" ? "+00:00" : match[:off].sub(/(\d{2})(\d{2})\z/, '\1:\2')
        Time.new(date.year, date.month, date.day, hour, min, sec, offset)
      else
        ActiveSupport::TimeZone[Receipt::TIME_ZONE].local(date.year, date.month, date.day, hour, min, sec)
      end
    end
  end
end
