# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flinks::TransactionImporter do
  fixtures :users

  let(:alice) { users(:alice) }
  let(:connection) do
    FlinksConnection.create!(
      user: alice,
      login_id: "test-login",
      request_id: "test-request",
      institution: "FlinksCapital"
    )
  end

  # Flinks::Client is already tested with VCR cassettes in client_spec.
  # Here we test the transformation and DB logic with a fake client.
  let(:fake_client) do
    client = instance_double(Flinks::Client)
    allow(client).to receive(:authorize_with_login_id).and_raise(Flinks::ApiError, "demo doesn't support reauth")
    allow(client).to receive(:fetch_transactions).and_return(flinks_transactions)
    client
  end

  let(:flinks_transactions) do
    [
      { date: "2026-04-01", description: "GROCERY STORE", debit: 45.99, credit: nil, account_id: "acct-1", last_four_digits: "9649" },
      { date: "2026-04-02", description: "PAYMENT RECEIVED", debit: nil, credit: 500.00, account_id: "acct-1", last_four_digits: "9649" },
      { date: "2026-04-03", description: "GAS STATION", debit: 62.15, credit: nil, account_id: "acct-1", last_four_digits: "9649" },
    ]
  end

  subject { described_class.new(connection, client: fake_client) }

  it "creates credit card transactions for the user" do
    expect { subject.import }.to change { alice.credit_card_transactions.count }.by(3)
  end

  it "transforms debit amounts to integer cents" do
    subject.import
    tx = alice.credit_card_transactions.find_by(details: "GROCERY STORE")
    expect(tx.debit).to eq(4599)
    expect(tx.credit).to be_nil
  end

  it "transforms credit amounts to integer cents" do
    subject.import
    tx = alice.credit_card_transactions.find_by(details: "PAYMENT RECEIVED")
    expect(tx.credit).to eq(50000)
    expect(tx.debit).to be_nil
  end

  it "sets user_id from the connection" do
    subject.import
    alice.credit_card_transactions.where(details: flinks_transactions.map { |t| t[:description] }).each do |tx|
      expect(tx.user_id).to eq(alice.id)
    end
  end

  it "sets card_number from account last_four_digits" do
    subject.import
    tx = alice.credit_card_transactions.find_by(details: "GROCERY STORE")
    expect(tx.card_number).to eq("9649")
  end

  it "returns imported and skipped counts" do
    result = subject.import
    expect(result[:imported]).to eq(3)
    expect(result[:skipped]).to eq(0)
  end

  it "skips duplicates on second import" do
    subject.import
    result = subject.import
    expect(result[:imported]).to eq(0)
    expect(result[:skipped]).to eq(3)
  end

  it "updates last_synced_at on the connection" do
    subject.import
    expect(connection.reload.last_synced_at).to be_present
  end
end
