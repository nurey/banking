# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReceiptValidator do
  let(:good) do
    {
      subtotal: 746, tax: 97, total: 843, taxes: [ { label: "HST", rate: 13.0, amount: 97 } ],
      line_totals: [ 97, 649 ], purchased_on: Date.new(2026, 10, 24), confidences: [ 1.0, 1.0, 1.0 ]
    }
  end

  def reasons(**overrides) = described_class.reasons(**good, **overrides)

  it "has no reasons for a consistent receipt" do
    expect(reasons).to eq([])
  end

  it "allows one cent per tax line plus one" do
    expect(reasons(subtotal: 748, total: 845)).to eq([])
    expect(reasons(subtotal: 749, total: 846)).to eq(%w[items_sum_mismatch])
    expect(reasons(total: 846)).to eq(%w[totals_mismatch])
  end

  it "flags items that don't add up to the subtotal" do
    expect(reasons(line_totals: [ 97, 600 ])).to eq(%w[items_sum_mismatch])
  end

  it "flags subtotal plus tax not matching the total" do
    expect(reasons(total: 900)).to eq(%w[totals_mismatch])
  end

  it "uses the sum of the items when there's no subtotal" do
    expect(reasons(subtotal: nil)).to eq([])
    expect(reasons(subtotal: nil, total: 900)).to eq(%w[totals_mismatch])
  end

  it "counts negative discount items" do
    expect(reasons(line_totals: [ 97, 749, -100 ])).to eq([])
  end

  it "treats a missing tax as zero" do
    expect(reasons(tax: nil, taxes: [], total: 746)).to eq([])
  end

  it "flags missing fields" do
    expect(reasons(total: nil)).to eq(%w[total_missing])
    expect(reasons(purchased_on: nil)).to eq(%w[date_missing])
    expect(reasons(line_totals: [], subtotal: nil, total: 97, tax: nil, taxes: [])).to eq(%w[no_items totals_mismatch])
  end

  it "flags low confidence by the share of lines below 1.0, not the mean" do
    expect(reasons(confidences: [ 1.0, 1.0, 0.5 ])).to eq(%w[low_confidence])
    expect(reasons(confidences: [ 1.0, 1.0, 1.0, 0.3 ])).to eq([])
    expect(reasons(confidences: [])).to eq([])
  end

  it "returns reasons in a stable order" do
    expect(reasons(total: nil, purchased_on: nil, line_totals: [], confidences: [ 0.5 ]))
      .to eq(%w[total_missing date_missing no_items items_sum_mismatch low_confidence])
  end
end
