# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlinksImportJob, type: :job do
  fixtures :users

  let(:alice) { users(:alice) }
  let(:fake_transactions) do
    [
      { date: "2026-04-01", description: "JOB TEST TX", debit: 10.00, credit: nil, account_id: "a", last_four_digits: "1234" },
    ]
  end

  before do
    fake_client = instance_double(Flinks::Client)
    allow(fake_client).to receive(:authorize_with_login_id).and_raise(Flinks::ApiError, "demo")
    allow(fake_client).to receive(:fetch_transactions).and_return(fake_transactions)
    allow(Flinks::Client).to receive(:new).and_return(fake_client)
  end

  it "imports transactions for active connections" do
    FlinksConnection.create!(
      user: alice,
      login_id: "test-login",
      request_id: "test-request",
      institution: "FlinksCapital",
      status: "active"
    )

    expect {
      described_class.perform_now
    }.to change { alice.credit_card_transactions.count }.by(1)
  end

  it "skips inactive connections" do
    FlinksConnection.create!(
      user: alice,
      login_id: "test-login",
      request_id: "test-request",
      institution: "FlinksCapital",
      status: "inactive"
    )

    expect {
      described_class.perform_now
    }.not_to change { alice.credit_card_transactions.count }
  end
end
