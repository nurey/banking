# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReceiptParser::Steps::ExtractMerchant do
  def merchant(*texts)
    described_class.new.call(context(rows: rows(*texts))).merchant
  end

  it "takes the first row with a name and title-cases it" do
    expect(merchant("LOBLAWS #1234", "2026-10-24")).to eq("Loblaws")
    expect(merchant("SHOPPERS DRUG MART")).to eq("Shoppers Drug Mart")
  end

  it "never ends a name with a period or other trailing punctuation" do
    expect(merchant("Longos.")).to eq("Longos")
    expect(merchant("METRO .")).to eq("Metro")
    expect(merchant("NO FRILLS,:")).to eq("No Frills")
  end

  it "skips welcome lines, addresses, phone numbers, URLs and store numbers" do
    expect(merchant(
      "WELCOME", "BIENVENUE", "STORE #1234", "123 MAIN ST", "TORONTO ON M5V 2T6",
      "(416) 555-0199", "TEL 416.555.0199", "www.example.ca", "ORDER 2026-10-24 11:40", "** ", "TIM HORTONS"
    )).to eq("Tim Hortons")
  end

  it "only looks at page 0" do
    page1 = rows("COSTCO", page: 1)
    ctx = context(rows: rows("12", page: 0) + page1)
    expect(described_class.new.call(ctx).merchant).to be_nil
  end

  it "skips rows with amounts and rows with too few letters" do
    expect(merchant("AB", "TOTAL 1.00", "METRO")).to eq("Metro")
  end
end
