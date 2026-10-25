# rbs_inline: enabled
# frozen_string_literal: true

# Decides whether a receipt needs a person to look at it. Runs on the parser's
# result and again on every PATCH without confirm, so both agree on the rules.
module ReceiptValidator
  # A line counts as low confidence below 1.0: at `.accurate`, Vision reports
  # 0.5 or 1.0, rarely 0.3, so a mean says little. Tune this from the corpus (M3a).
  LOW_CONFIDENCE_SHARE = 0.30

  # @rbs subtotal: Integer?
  # @rbs tax: Integer?
  # @rbs total: Integer?
  # @rbs taxes: Array[untyped]
  # @rbs line_totals: Array[Integer]
  # @rbs purchased_on: Date?
  # @rbs confidences: Array[Float]
  # @rbs return: Array[String]
  def self.reasons(subtotal:, tax:, total:, taxes:, line_totals:, purchased_on:, confidences:)
    tolerance = taxes.size + 1 # one cent per tax line, plus one
    items_sum = line_totals.sum
    reasons = []
    reasons << "total_missing" if total.nil?
    reasons << "date_missing" if purchased_on.nil?
    reasons << "no_items" if line_totals.empty?
    reasons << "items_sum_mismatch" if subtotal && (items_sum - subtotal).abs > tolerance
    reasons << "totals_mismatch" if total && ((subtotal || items_sum) + tax.to_i - total).abs > tolerance
    reasons << "low_confidence" if low_confidence?(confidences)
    reasons
  end

  # @rbs result: ReceiptParser::Result
  # @rbs confidences: Array[Float]
  # @rbs return: Array[String]
  def self.for_result(result, confidences:)
    reasons(
      subtotal: result.subtotal, tax: result.tax, total: result.total, taxes: result.taxes,
      line_totals: result.items.map(&:line_total), purchased_on: result.purchased_on, confidences:
    )
  end

  # @rbs receipt: Receipt
  # @rbs return: Array[String]
  def self.for_receipt(receipt)
    reasons(
      subtotal: receipt.subtotal, tax: receipt.tax, total: receipt.total, taxes: receipt.taxes,
      line_totals: receipt.line_items.map(&:line_total), purchased_on: receipt.purchased_on,
      confidences: receipt.ocr_lines.map { it["confidence"].to_f }
    )
  end

  # @rbs confidences: Array[Float]
  # @rbs return: bool
  def self.low_confidence?(confidences)
    return false if confidences.empty?

    confidences.count { it < 1.0 }.fdiv(confidences.size) > LOW_CONFIDENCE_SHARE
  end
end
