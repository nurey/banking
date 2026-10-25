# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReceiptParser::Steps::ExtractTaxes do
  def extract(*classified_rows)
    described_class.new.call(context(classified: classified_rows))
  end

  it "makes one tax per tax row and sums them" do
    result = extract(
      classified("SOUS-TOTAL 10.00", :subtotal),
      classified("TPS 5% 0.50", :tax, rate: 5.0),
      classified("TVQ 9.975% 1.00", :tax, rate: 9.975)
    )
    expect(result.taxes).to eq([
      ReceiptParser::Tax.new(label: "TPS", rate: 5.0, amount: 50),
      ReceiptParser::Tax.new(label: "TVQ", rate: 9.975, amount: 100)
    ])
    expect(result.tax).to eq(150)
  end

  it "labels plain TAX rows" do
    expect(extract(classified("SALES TAX 0.13", :tax)).taxes.map(&:label)).to eq([ "TAX" ])
  end

  it "skips tax rows without an amount" do
    expect(extract(classified("HST INCLUDED", :tax)).taxes).to eq([])
  end

  it "leaves tax nil when there are no tax rows" do
    result = extract(classified("BANANAS 0.97", :item))
    expect(result.taxes).to eq([])
    expect(result.tax).to be_nil
  end
end
