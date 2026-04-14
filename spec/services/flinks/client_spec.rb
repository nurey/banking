# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flinks::Client do
  let(:client) { described_class.new }
  let(:creds) { Rails.application.credentials.flinks }

  describe "#generate_token", vcr: { cassette_name: "flinks/generate_token" } do
    it "returns a temporary authorize token" do
      token = client.generate_token
      expect(token).to be_a(String)
      expect(token).to be_present
    end
  end

  describe "#authorize", vcr: { cassette_name: "flinks/authorize" } do
    it "returns a request_id and login info" do
      result = client.authorize(
        institution: "FlinksCapital",
        username: creds.demo_username,
        password: creds.demo_password
      )
      expect(result[:request_id]).to be_present
      expect(result[:login_id]).to be_present
      expect(result[:institution]).to eq("FlinksCapital")
    end
  end

  describe "#fetch_transactions", vcr: { cassette_name: "flinks/fetch_transactions" } do
    it "returns an array of transactions with expected fields" do
      auth = client.authorize(
        institution: "FlinksCapital",
        username: creds.demo_username,
        password: creds.demo_password
      )
      transactions = client.fetch_transactions(request_id: auth[:request_id])
      expect(transactions).to be_an(Array)
      expect(transactions).not_to be_empty

      tx = transactions.first
      expect(tx).to have_key(:date)
      expect(tx).to have_key(:description)
      expect(tx[:debit].nil? || tx[:debit].is_a?(Numeric)).to be true
      expect(tx[:credit].nil? || tx[:credit].is_a?(Numeric)).to be true
    end
  end

  describe "error handling" do
    it "raises ApiError on invalid credentials", vcr: { cassette_name: "flinks/authorize_invalid" } do
      expect {
        client.authorize(institution: "FlinksCapital", username: "bad", password: "bad")
      }.to raise_error(Flinks::ApiError)
    end
  end
end
