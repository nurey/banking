# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReceiptParser::Steps::ExtractDate do
  let(:captured_at) { Time.zone.parse("2026-10-24T11:42:10-04:00") }

  def extract(*texts, captured_at: self.captured_at)
    described_class.new.call(context(rows: rows(*texts), captured_at:))
  end

  def toronto(string) = ActiveSupport::TimeZone["America/Toronto"].parse(string)

  {
    "2026-10-24" => "2026-10-24",
    "DATE: 2026/10/24" => "2026-10-24",
    "24/10/2026" => "2026-10-24",
    "10/24/2026" => "2026-10-24",
    "10/24/26" => "2026-10-24",
    "24-Oct-2026" => "2026-10-24",
    "Oct 24, 2026" => "2026-10-24",
    "OCT 24 2026" => "2026-10-24",
    "24 octobre 2026" => "2026-10-24",
    "24 oct. 2026" => "2026-10-24",
    "1 août 2026" => "2026-08-01",
    "12 déc 2025" => "2025-12-12"
  }.each do |text, expected|
    it "reads #{text.inspect}" do
      expect(extract("LOBLAWS", text).purchased_on).to eq(Date.iso8601(expected))
    end
  end

  it "picks the reading of an ambiguous date closest to, and not after, the capture" do
    result = extract("05/10/2026")
    expect(result.purchased_on).to eq(Date.new(2026, 10, 5))
    expect(result.warnings).to eq([ :ambiguous_date ])

    expect(extract("10/05/2026").purchased_on).to eq(Date.new(2026, 10, 5))
  end

  it "doesn't warn when only one reading is a valid date" do
    expect(extract("24/10/2026").warnings).to eq([])
  end

  it "skips a later date such as a return-by date in favour of one before the capture" do
    expect(extract("RETURN BY 2026-11-23", "2026-10-24").purchased_on).to eq(Date.new(2026, 10, 24))
  end

  it "takes the first date when there's no capture time" do
    expect(extract("2026-10-20", "2026-10-21", captured_at: nil).purchased_on).to eq(Date.new(2026, 10, 20))
  end

  it "reads a time on the date's row in America/Toronto" do
    result = extract("2026-10-24 11:40")
    expect(result.purchased_at).to eq(toronto("2026-10-24 11:40"))
    expect(extract("10/24/2026 2:05 PM").purchased_at).to eq(toronto("2026-10-24 14:05"))
    expect(extract("10/24/2026 12:05 AM").purchased_at).to eq(toronto("2026-10-24 00:05"))
  end

  it "reads a time on the next row" do
    expect(extract("DATE 2026-10-24", "TIME 11:40:12").purchased_at).to eq(toronto("2026-10-24 11:40:12"))
  end

  it "uses a printed offset" do
    expect(extract("2026-10-24 11:40 -05:00").purchased_at).to eq(Time.iso8601("2026-10-24T11:40:00-05:00"))
  end

  it "leaves purchased_at nil without a time" do
    expect(extract("2026-10-24").purchased_at).to be_nil
  end

  it "ignores impossible dates and finds nothing in plain text" do
    result = extract("31/31/2026", "TEL 416-555-0199")
    expect(result.purchased_on).to be_nil
    expect(result.purchased_at).to be_nil
  end
end
