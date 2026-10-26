# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReceiptParser::Steps::ExtractMerchant do
  def merchant(*texts, known_addresses: {})
    described_class.new(known_addresses:).call(context(rows: rows(*texts))).merchant
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

  it "skips a city and province line" do
    expect(merchant("Toronto, Ontario", "CORNER GROCER")).to eq("Corner Grocer")
    expect(merchant("MONTRÉAL, QC", "TORONTO ON", "IGA")).to eq("Iga")
  end

  it "stops at the transaction details when no name is printed above them" do
    expect(merchant("123 Main Street", "Toronto, Ontario", "(416) 555-0199", "Lane: 001", "Cashier: 156", "** MEAT **")).to be_nil
    expect(merchant("Tel: (416) 555-0199", "METRO")).to eq("Metro")
  end

  it "names a store that prints only its address from the address" do
    known_addresses = { "123 MAIN": "Corner Grocer" }
    expect(merchant("123 Main Street", "Toronto, Ontario", "Lane: 001", known_addresses:)).to eq("Corner Grocer")
    expect(merchant("123  MAIN ST", "TORONTO ON", known_addresses:)).to eq("Corner Grocer")
    expect(merchant("1234 Main Street", "Toronto, Ontario", known_addresses:)).to be_nil
    expect(merchant("123 Mainland Ave", known_addresses:)).to be_nil
  end

  it "reads the known addresses from the encrypted credentials" do
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig).with(:receipt_parser, :known_addresses).and_return({ "123 MAIN": "Corner Grocer" })
    expect(described_class.new.call(context(rows: rows("123 Main Street"))).merchant).to eq("Corner Grocer")
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
