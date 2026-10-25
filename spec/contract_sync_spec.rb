# frozen_string_literal: true

require "rails_helper"

# The receipts API contract is owned by the receipt-scanner repo (its contract/
# folder), and the Swift tests load it from there. This repo keeps a copy so its
# specs run without that repo checked out. This spec catches the two drifting.
RSpec.describe "receipt-scanner API contract" do
  upstream = Pathname(ENV.fetch("RECEIPT_CONTRACT_DIR", File.expand_path("~/Devel/receipt-scanner/contract")))
  local = Rails.root.join("spec/fixtures/contract")

  if upstream.directory?
    upstream.glob("*.json").each do |path|
      it "matches #{path.basename}" do
        expect(local.join(path.basename)).to exist
        expect(local.join(path.basename).read).to eq(path.read)
      end
    end
  else
    it "is checked against receipt-scanner/contract" do
      skip "#{upstream} not found; set RECEIPT_CONTRACT_DIR"
    end
  end
end
