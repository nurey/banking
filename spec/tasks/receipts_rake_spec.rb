# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "receipts rake tasks" do
  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.none? { it.name == "receipts:reparse" } }

  let(:capture) { JSON.parse(Rails.root.join("spec/fixtures/contract/create_receipt.request.json").read) }

  def receipt(**attrs)
    Receipt.create!(
      capture_id: SecureRandom.uuid, parse_status: "failed", raw_text: capture["raw_text"],
      ocr_lines: capture["ocr_lines"], captured_at: capture["captured_at"],
      images: [ { io: StringIO.new(file_fixture("page.jpg").binread), filename: "p.jpg", content_type: "image/jpeg" } ],
      **attrs
    )
  end

  def run(name, *args, env: {})
    task = Rake::Task[name]
    task.reenable
    ClimateEnv.with(env) { expect { task.invoke(*args) }.to output.to_stdout }
  end

  module ClimateEnv
    def self.with(env)
      previous = env.keys.to_h { [ it, ENV[it] ] }
      env.each { ENV[_1] = _2 }
      yield
    ensure
      previous.each { ENV[_1] = _2 }
    end
  end

  it "receipts:reparse re-parses outdated receipts and leaves current and confirmed ones" do
    outdated = receipt(parser_version: 0)
    confirmed = receipt(parse_status: "confirmed", parser_version: 0, merchant: "Mine")

    run("receipts:reparse")

    expect(outdated.reload.parser_version).to eq(ReceiptParser::VERSION)
    expect(confirmed.reload).to have_attributes(parser_version: 0, merchant: "Mine")
  end

  it "receipts:reparse[id] re-parses one receipt even if it's current, by id or capture_id" do
    current = receipt
    current.apply_parse(ReceiptParser.call(ocr_lines: current.ocr_lines, captured_at: current.captured_at))
    current.update!(merchant: "Stale")

    run("receipts:reparse", current.id.to_s)
    expect(current.reload.merchant).to eq("Loblaws")

    current.update!(merchant: "Stale")
    run("receipts:reparse", current.capture_id)
    expect(current.reload.merchant).to eq("Loblaws")
  end

  it "receipts:reparse[id] skips a confirmed receipt unless FORCE=1, and then rewrites only parsed" do
    confirmed = receipt(parse_status: "confirmed", merchant: "Mine", parser_version: 0)

    run("receipts:reparse", confirmed.id.to_s)
    expect(confirmed.reload.parser_version).to eq(0)

    run("receipts:reparse", confirmed.id.to_s, env: { "FORCE" => "1" })
    expect(confirmed.reload).to have_attributes(parser_version: ReceiptParser::VERSION, merchant: "Mine")
    expect(confirmed.parsed["merchant"]).to eq("Loblaws")
  end
end
