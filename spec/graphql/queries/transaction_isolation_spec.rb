# frozen_string_literal: true

require "rails_helper"

RSpec.describe "transaction isolation" do
  fixtures :users, :credit_card_transactions, :notes

  let(:query) do
    <<~GQL
      query {
        creditCardTransactions {
          id
          details
        }
      }
    GQL
  end

  it "returns only the current user's transactions" do
    alice = users(:alice)
    result = execute_graphql(query, context: { current_user: alice })
    ids = result.dig("data", "creditCardTransactions").map { |t| t["id"].to_i }

    alice_tx_ids = CreditCardTransaction.where(user: alice, tx_date: 12.months.ago..).pluck(:id)
    bob_tx_ids = CreditCardTransaction.where(user: users(:bob)).pluck(:id)

    expect(ids).to match_array(alice_tx_ids)
    bob_tx_ids.each { |id| expect(ids).not_to include(id) }
  end

  it "returns empty when user has no transactions" do
    bob = users(:bob)
    result = execute_graphql(query, context: { current_user: bob })
    transactions = result.dig("data", "creditCardTransactions")

    expect(transactions).to eq([])
  end
end
