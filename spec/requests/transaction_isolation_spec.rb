# frozen_string_literal: true

require "rails_helper"

RSpec.describe "REST transaction isolation", type: :request do
  fixtures :users, :credit_card_transactions

  def login_as(user)
    post "/session",
      params: { email_address: user.email_address, password: "password123" },
      headers: { "Origin" => ENV["CORS_ORIGINS"] || "http://localhost:3000" }
  end

  it "index returns only the current user's transactions" do
    alice = users(:alice)
    login_as(alice)
    get "/credit_card_transactions"

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    ids = body.dig("data").map { |t| t.dig("id").to_i }

    alice_tx_ids = CreditCardTransaction.where(user: alice).pluck(:id)
    expect(ids).to match_array(alice_tx_ids)
  end

  it "debits returns only the current user's debits" do
    alice = users(:alice)
    login_as(alice)
    get "/credit_card_transactions/debits"

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    ids = body.dig("data").map { |t| t.dig("id").to_i }

    bob_tx_ids = CreditCardTransaction.where(user: users(:bob)).pluck(:id)
    bob_tx_ids.each { |id| expect(ids).not_to include(id) }
  end
end
