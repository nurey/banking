# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ReceiptParser pipeline" do
  steps = ReceiptParser::STEPS
  shared = ReceiptParser::Context::SHARED

  it "declares READS and WRITES on every step, without the shared fields" do
    steps.each do |step|
      expect(step::READS).to be_frozen
      expect(step::WRITES).to be_frozen
      expect((step::READS + step::WRITES) & shared).to eq([]), "#{step} lists a shared field"
      expect(step::READS + step::WRITES - ReceiptParser::Context.members).to eq([]), "#{step} lists an unknown field"
    end
  end

  it "only reads inputs or fields an earlier step wrote" do
    available = ReceiptParser::Context::INPUTS.dup
    steps.each do |step|
      expect(step::READS - available).to eq([]), "#{step} reads #{step::READS - available} before anything writes it"
      available |= step::WRITES
    end
  end

  it "has exactly one writer for every output field" do
    ReceiptParser::Context::OUTPUTS.each do |field|
      writers = steps.select { it::WRITES.include?(field) }
      expect(writers.size).to eq(1), "#{field} is written by #{writers.map(&:name).presence || 'nothing'}"
    end
  end

  it "records one trace entry per step" do
    result = ReceiptParser.call(ocr_lines: [ ocr_line("TOTAL 1.00") ], captured_at: nil)
    expect(result.trace.map { it[:step] }).to eq(steps.map { it.name.demodulize })
  end

  it "records changed fields, array fields as counts, and added warnings" do
    result = ReceiptParser.call(ocr_lines: [ ocr_line("THANK YOU") ], captured_at: nil)
    build_rows = result.trace.find { it[:step] == "BuildRows" }
    pick_total = result.trace.find { it[:step] == "PickTotal" }

    expect(build_rows).to eq({ step: "BuildRows", changed: { rows: 1 } })
    expect(pick_total).to eq({ step: "PickTotal", changed: {}, warnings: [ :no_total_candidate ] })
  end

  it "runs only the steps it's given" do
    result = ReceiptParser.call(ocr_lines: [ ocr_line("TOTAL 1.00") ], captured_at: nil, steps: steps.first(2))
    expect(result.trace.size).to eq(2)
    expect(result.total).to be_nil
  end

  it "wraps a step's error in a StepError naming the step" do
    exploding = Class.new do
      const_set(:READS, [].freeze)
      const_set(:WRITES, [].freeze)
      def self.name = "ReceiptParser::Steps::Exploding"
      def call(_ctx) = raise(NoMethodError, "undefined method 'boom'")
    end

    expect { ReceiptParser.call(ocr_lines: [], captured_at: nil, steps: [ exploding ]) }
      .to raise_error(ReceiptParser::StepError, "Exploding failed: undefined method 'boom'") { |error|
        expect(error.step).to eq(exploding)
        expect(error.cause).to be_a(NoMethodError)
      }
  end
end
