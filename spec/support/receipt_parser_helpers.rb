# frozen_string_literal: true

module ReceiptParserHelpers
  # One OCR line as the phone sends it: normalized, top-left origin.
  def ocr_line(text, x: 0.1, y: 0.1, w: 0.3, h: 0.02, page: 0, confidence: 1.0)
    { "page" => page, "text" => text, "x" => x, "y" => y, "w" => w, "h" => h, "confidence" => confidence }
  end

  # Rows as NormalizeTokens leaves them, one per string, top to bottom.
  def rows(*texts, page: 0)
    texts.each_with_index.map do |text, i|
      cell = ReceiptParser::Line.new(page:, text:, x: 0.1, y: 0.05 + i * 0.03, w: 0.8, h: 0.02, confidence: 1.0)
      ReceiptParser::Row.new(page:, y: cell.y, height: cell.h, cells: [ cell ], money: ReceiptParser::Money.scan(text))
    end
  end

  def context(**fields)
    ReceiptParser::Context.start(ocr_lines: [], captured_at: nil).with(**fields)
  end

  # A classified row built by hand, so specs for later steps don't depend on ClassifyRows.
  def classified(text, kind, **attrs)
    ReceiptParser::ClassifiedRow.new(row: rows(text).first, kind:, rate: nil, quantity: nil, **attrs)
  end
end

RSpec.configure do |config|
  config.include ReceiptParserHelpers, file_path: %r{spec/models/receipt_(parser|validator)}
end
