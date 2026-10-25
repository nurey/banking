# rbs_inline: enabled
# frozen_string_literal: true

# Turns the phone's OCR lines into merchant, date, items, taxes, and total.
#
# The parser is a list of step commands, each an object with one
# #call(context) → context. The runner threads one immutable Context through
# them in order and records a trace entry after each. Steps declare the fields
# they READ and WRITE; spec/models/receipt_parser/pipeline_spec.rb holds them to it.
#
# Warnings are the parser's own notes. Review reasons come only from
# ReceiptValidator, which runs on the result, so PATCH and the parser agree.
module ReceiptParser
  # Bump whenever any step's output changes; `receipts:reparse` re-runs older receipts.
  VERSION = 1

  STEPS = [
    Steps::BuildRows, Steps::NormalizeTokens, Steps::ClassifyRows, Steps::ExtractItems,
    Steps::ExtractTaxes, Steps::PickTotal, Steps::ExtractDate, Steps::ExtractMerchant
  ].freeze

  class StepError < StandardError
    # @rbs @step: Class

    attr_reader :step

    # @rbs step: Class
    # @rbs error: StandardError
    def initialize(step, error)
      @step = step
      super("#{step.name.demodulize} failed: #{error.message}")
    end
  end

  # @rbs ocr_lines: Array[Hash[String, untyped]]
  # @rbs captured_at: Time?
  # @rbs steps: Array[Class]
  # @rbs return: Result
  def self.call(ocr_lines:, captured_at:, steps: STEPS)
    context = steps.reduce(Context.start(ocr_lines:, captured_at:)) do |ctx, step|
      out = step.new.call(ctx)
      out.with(trace: ctx.trace + [ Trace.entry(step, ctx, out) ])
    rescue StandardError => e
      raise StepError.new(step, e) # the original error stays available as #cause
    end
    Result.from(context)
  end
end
