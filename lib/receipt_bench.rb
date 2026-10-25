# rbs_inline: enabled
# frozen_string_literal: true

# Scores parser output per OCR preprocessing variant, for the receipt-scanner
# preprocessing experiment (its PLAN.md, iOS §3a). Reads `<name>.<variant>.ocr.json`
# captures (written by `swift run ocr-bench`) and `<name>.expected.json` answers
# from one directory. Never touches the database.
class ReceiptBench
  FIELDS = %w[merchant purchased_on subtotal tax total card_last_four].freeze

  Score = Struct.new(
    :receipts, :total_correct, :items_found, :items_expected, :parsed,
    :lines, :low_confidence_lines, :page_ms, :blame,
    keyword_init: true
  ) do
    # @rbs return: Float
    def item_recall = items_expected.zero? ? 1.0 : items_found.fdiv(items_expected)

    # @rbs return: Float
    def consistency = receipts.zero? ? 0.0 : parsed.fdiv(receipts)

    # @rbs return: Float
    def low_confidence_share = lines.zero? ? 0.0 : low_confidence_lines.fdiv(lines)

    # @rbs return: Float?
    def mean_page_ms = page_ms.empty? ? nil : page_ms.sum.fdiv(page_ms.size)
  end

  Report = Struct.new(:variants, :skipped) do
    # @rbs return: String
    def to_s
      header = format("%-28s %8s %13s %11s %11s %9s %9s", "variant", "receipts", "total+date", "item recall", "consistent", "conf<1.0", "ms/page")
      rows = variants.sort.map do |name, score|
        format(
          "%-28s %8d %7d (%3.0f%%) %10.0f%% %10.0f%% %8.0f%% %9s",
          name, score.receipts, score.total_correct, 100.0 * score.total_correct / [ score.receipts, 1 ].max,
          100 * score.item_recall, 100 * score.consistency, 100 * score.low_confidence_share,
          score.mean_page_ms&.round || "-"
        )
      end
      blame = variants.sort.flat_map do |name, score|
        score.blame.flat_map do |step, fields|
          fields.map { |field, count| "#{name}: #{field} wrong on #{count} receipt#{'s' unless count == 1} → #{step}" }
        end
      end
      skipped_note = skipped.any? ? [ "", "No expected file for: #{skipped.join(', ')}" ] : []
      [ header, *rows, "", *blame, *skipped_note ].join("\n") + "\n"
    end
  end

  # @rbs expected_item: Hash[String, untyped]
  # @rbs items: Array[ReceiptParser::Item]
  # @rbs return: bool
  def self.item_found?(expected_item, items)
    want = normalize(expected_item["description"])
    items.any? do |item|
      next false unless item.line_total == expected_item["line_total"]

      got = normalize(item.description)
      distance = DidYouMean::Levenshtein.distance(want, got)
      got.include?(want) || want.include?(got) && got.present? || distance <= [ want.size / 5, 1 ].max
    end
  end

  # @rbs text: String?
  # @rbs return: String
  def self.normalize(text) = text.to_s.downcase.gsub(/[^a-z0-9%]/, "")

  # @rbs dir: String | Pathname
  def initialize(dir)
    @dir = Pathname(dir)
  end

  # @rbs return: Report
  def run
    variants = Hash.new { |hash, key| hash[key] = Score.new(receipts: 0, total_correct: 0, items_found: 0, items_expected: 0, parsed: 0, lines: 0, low_confidence_lines: 0, page_ms: [], blame: {}) }
    skipped = []

    @dir.glob("*.*.ocr.json").sort.each do |path|
      name, variant = path.basename.to_s.delete_suffix(".ocr.json").split(".", 2)
      expected_path = @dir.join("#{name}.expected.json")
      next skipped << path.basename.to_s unless expected_path.exist?

      score(variants[variant], JSON.parse(path.read), JSON.parse(expected_path.read))
    end

    Report.new(variants.to_h, skipped)
  end

  private

  # @rbs score: Score
  # @rbs capture: Hash[String, untyped]
  # @rbs expected: Hash[String, untyped]
  # @rbs return: void
  def score(score, capture, expected)
    lines = capture.fetch("ocr_lines")
    confidences = lines.map { it["confidence"].to_f }
    result = ReceiptParser.call(ocr_lines: lines, captured_at: capture["captured_at"] && Time.iso8601(capture["captured_at"]))
    actual = result.as_json

    score.receipts += 1
    score.lines += lines.size
    score.low_confidence_lines += confidences.count { it < 1.0 }
    score.page_ms.concat(Array(capture.dig("ocr", "page_ms")))
    score.parsed += 1 if ReceiptValidator.for_result(result, confidences:).empty?
    score.total_correct += 1 if actual["total"] == expected["total"] && actual["purchased_on"] == expected["purchased_on"]

    wrong = FIELDS.select { expected.key?(it) && actual[it] != expected[it] }
    if expected.key?("items")
      found = expected["items"].count { self.class.item_found?(it, result.items) }
      score.items_found += found
      score.items_expected += expected["items"].size
      wrong << "items" if found < expected["items"].size || result.items.size != expected["items"].size
    end
    wrong.each { charge(score, it) }
  end

  # Each output field has exactly one writer (pipeline_spec), so a wrong field
  # points at one step.
  #
  # @rbs score: Score
  # @rbs field: String
  # @rbs return: void
  def charge(score, field)
    step = ReceiptParser::STEPS.find { it::WRITES.include?(field.to_sym) }.name.demodulize
    score.blame[step] ||= Hash.new(0)
    score.blame[step][field] += 1
  end
end
