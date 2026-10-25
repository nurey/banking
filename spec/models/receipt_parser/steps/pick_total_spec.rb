# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReceiptParser::Steps::PickTotal do
  def pick(*classified_rows)
    described_class.new.call(context(classified: classified_rows))
  end

  it "prefers the total candidate that equals the payment" do
    result = pick(
      classified("TOTAL 8.43", :total),
      classified("TOTAL 0.00", :total),
      classified("VISA 8.43", :payment)
    )
    expect(result.total).to eq(843)
  end

  it "otherwise takes the last candidate before the payment rows" do
    result = pick(
      classified("TOTAL 7.46", :total),
      classified("AMOUNT DUE 8.43", :total),
      classified("CASH 10.00", :payment),
      classified("TOTAL 1.57", :total)
    )
    expect(result.total).to eq(843)
  end

  it "takes the last candidate when there are no payment rows" do
    expect(pick(classified("TOTAL 7.46", :total), classified("TOTAL 8.43", :total)).total).to eq(843)
  end

  it "ignores candidates without an amount" do
    expect(pick(classified("TOTAL 8.43", :total), classified("TOTAL", :total)).total).to eq(843)
  end

  it "warns when there is no candidate" do
    result = pick(classified("BANANAS 0.97", :item))
    expect(result.total).to be_nil
    expect(result.warnings).to eq([ :no_total_candidate ])
  end
end
