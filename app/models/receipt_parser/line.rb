# rbs_inline: enabled
# frozen_string_literal: true

module ReceiptParser
  # One OCR line: normalized 0–1 within its page, top-left origin.
  Line = Data.define(:page, :text, :x, :y, :w, :h, :confidence) do
    # @rbs hash: Hash[String, untyped]
    # @rbs return: Line
    def self.from_h(hash)
      new(
        page: hash.fetch("page"), text: hash.fetch("text").to_s,
        x: hash.fetch("x").to_f, y: hash.fetch("y").to_f, w: hash.fetch("w").to_f, h: hash.fetch("h").to_f,
        confidence: hash.fetch("confidence").to_f
      )
    end

    # @rbs return: Float
    def center_y = y + h / 2
  end
end
