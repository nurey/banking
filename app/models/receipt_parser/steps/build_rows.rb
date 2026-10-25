# rbs_inline: enabled
# frozen_string_literal: true

module ReceiptParser::Steps
  # Vision often returns a description and its price as separate lines on the
  # same printed row. Per page, sort lines by vertical center and join those
  # within half the median line height of the row's mean center, then order
  # each row left to right.
  #
  # A skewed or curled page puts a row's right end lower (or higher) than its
  # left, and past half a line height the price lands on its own row. So the
  # centers are straightened first, by the slope that brings the most pairs of
  # lines onto the same height (a projection profile). Zero wins ties.
  class BuildRows
    READS = %i[ocr_lines].freeze
    WRITES = %i[rows].freeze

    # @rbs ctx: ReceiptParser::Context
    # @rbs return: ReceiptParser::Context
    def call(ctx)
      lines = ctx.ocr_lines.map { ReceiptParser::Line.from_h(it) }
      rows = lines.group_by(&:page).sort.flat_map { |page, page_lines| rows_for(page, page_lines) }
      ctx.with(rows:)
    end

    private

    # @rbs page: Integer
    # @rbs lines: Array[ReceiptParser::Line]
    # @rbs return: Array[ReceiptParser::Row]
    def rows_for(page, lines)
      height = median(lines.map(&:h))
      slope = skew(lines, height)
      straight = lines.to_h { [ it, straightened(it, slope) ] }

      groups = lines.sort_by { straight[it] }.each_with_object([]) do |line, rows|
        row = rows.last
        if row && (straight[line] - row.sum { straight[it] } / row.size).abs <= 0.5 * height
          row << line
        else
          rows << [ line ]
        end
      end

      groups.map do |group|
        cells = group.sort_by(&:x)
        ReceiptParser::Row.new(page:, y: cells.map(&:y).min, height: cells.map(&:h).max, cells:, money: [])
      end
    end

    SLOPES = (-20..20).map { it * 0.0025 }.freeze # about ±2.9°

    # @rbs lines: Array[ReceiptParser::Line]
    # @rbs height: Float
    # @rbs return: Float
    def skew(lines, height)
      return 0.0 if lines.size < 4

      near = 0.25 * height
      scores = SLOPES.to_h do |slope|
        centers = lines.map { straightened(it, slope) }.sort
        pairs = centers.each_with_index.sum do |center, i|
          centers[(i + 1)..].take_while { it - center < near }.size
        end
        [ slope, pairs ]
      end
      best = scores.values.max
      scores.select { |_, pairs| pairs == best }.keys.min_by(&:abs)
    end

    # @rbs line: ReceiptParser::Line
    # @rbs slope: Float
    # @rbs return: Float
    def straightened(line, slope) = line.center_y - slope * (line.x + line.w / 2)

    # @rbs values: Array[Float]
    # @rbs return: Float
    def median(values)
      sorted = values.sort
      mid = sorted.size / 2
      sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    end
  end
end
