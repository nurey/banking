# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReceiptParser::Money do
  it "ignores amounts too large to store as cents" do
    expect(described_class.scan("TOTAL 99,999,999.99 21,474,836.48 21,474,836.47")).to eq([ 2_147_483_647 ])
  end
end
