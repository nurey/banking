# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreditCardTransaction do
  describe "#card_last_four" do
    def last_four(card_number)
      described_class.new(card_number: card_number).card_last_four
    end

    it "extracts the last four from a partially masked card number" do
      expect(last_four("5555********4242")).to eq("4242")
    end

    it "extracts the last four from a fully masked prefix" do
      expect(last_four("************1111")).to eq("1111")
    end

    it "returns a bare last-four unchanged" do
      expect(last_four("1234")).to eq("1234")
    end

    it "never returns more than the last four of an unmasked PAN" do
      expect(last_four("6701883850149315")).to eq("9315")
    end

    it "ignores spaces and dashes" do
      expect(last_four("4111-****-****-0004")).to eq("0004")
    end

    it "returns nil when there are no digits" do
      expect(last_four(nil)).to be_nil
      expect(last_four("")).to be_nil
      expect(last_four("   ")).to be_nil
      expect(last_four("****************")).to be_nil
    end
  end
end
