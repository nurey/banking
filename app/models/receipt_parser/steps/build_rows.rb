# rbs_inline: enabled
# frozen_string_literal: true

module ReceiptParser::Steps
  # Vision often returns a description and its price as separate lines on the
  # same printed row. Per page, sort lines by vertical center and join those
  # within half the median line height of the row's mean center, then order
  # each row left to right.
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
      tolerance = 0.5 * median(lines.map(&:h))
      groups = lines.sort_by(&:center_y).each_with_object([]) do |line, rows|
        row = rows.last
        if row && (line.center_y - row.sum(&:center_y) / row.size).abs <= tolerance
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

    # @rbs values: Array[Float]
    # @rbs return: Float
    def median(values)
      sorted = values.sort
      mid = sorted.size / 2
      sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    end
  end
end
