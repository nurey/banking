# frozen_string_literal: true

require "rails_helper"

RSpec.describe "creditCardTransactions query" do
  fixtures :credit_card_transactions, :notes

  let(:query) do
    <<~GQL
      query($sort: [CreditCardTransactionSort!], $showAnnotated: Boolean, $showCredits: Boolean) {
        creditCardTransactions(sort: $sort, showAnnotated: $showAnnotated, showCredits: $showCredits) {
          id
          txDate
          details
          debit
          credit
          cardNumber
          createdAt
          updatedAt
          note {
            id
            detail
          }
        }
      }
    GQL
  end

  def transaction_ids(result)
    result.dig("data", "creditCardTransactions").map { |t| t["id"].to_i }
  end

  it "returns recent transactions within 12 months" do
    result = execute_graphql(query)
    ids = transaction_ids(result)

    expect(ids).to include(
      credit_card_transactions(:recent_debit).id,
      credit_card_transactions(:annotated_debit).id,
      credit_card_transactions(:recent_credit).id
    )
  end

  it "excludes transactions older than 12 months" do
    result = execute_graphql(query)
    ids = transaction_ids(result)

    expect(ids).not_to include(credit_card_transactions(:old_debit).id)
  end

  it "includes transactions at the 12-month boundary" do
    result = execute_graphql(query)
    ids = transaction_ids(result)

    expect(ids).to include(credit_card_transactions(:boundary_debit).id)
  end

  it "returns all scalar fields correctly" do
    result = execute_graphql(query)
    tx_data = result.dig("data", "creditCardTransactions").find do |t|
      t["id"].to_i == credit_card_transactions(:recent_debit).id
    end
    tx = credit_card_transactions(:recent_debit)

    expect(tx_data["txDate"]).to eq(tx.tx_date.iso8601)
    expect(tx_data["details"]).to eq(tx.details)
    expect(tx_data["debit"]).to eq(tx.debit.to_f)
    expect(tx_data["credit"]).to be_nil
    expect(tx_data["cardNumber"]).to eq(tx.card_number)
    expect(tx_data["createdAt"]).to be_present
    expect(tx_data["updatedAt"]).to be_present
  end

  it "returns the associated note when present" do
    result = execute_graphql(query)
    tx_data = result.dig("data", "creditCardTransactions").find do |t|
      t["id"].to_i == credit_card_transactions(:annotated_debit).id
    end

    expect(tx_data["note"]).to be_present
    expect(tx_data["note"]["detail"]).to eq("Business dinner expense")
  end

  it "returns null note when absent" do
    result = execute_graphql(query)
    tx_data = result.dig("data", "creditCardTransactions").find do |t|
      t["id"].to_i == credit_card_transactions(:recent_debit).id
    end

    expect(tx_data["note"]).to be_nil
  end

  it "excludes annotated transactions when showAnnotated is false" do
    result = execute_graphql(query, variables: { "showAnnotated" => false })
    ids = transaction_ids(result)

    expect(ids).not_to include(credit_card_transactions(:annotated_debit).id)
    expect(ids).to include(credit_card_transactions(:recent_debit).id)
  end

  it "excludes credit transactions when showCredits is false" do
    result = execute_graphql(query, variables: { "showCredits" => false })
    ids = transaction_ids(result)

    expect(ids).not_to include(credit_card_transactions(:recent_credit).id)
    expect(ids).to include(credit_card_transactions(:recent_debit).id)
  end

  it "sorts by txDateAsc" do
    result = execute_graphql(query, variables: { "sort" => ["txDateAsc"] })
    dates = result.dig("data", "creditCardTransactions").map { |t| t["txDate"] }

    expect(dates).to eq(dates.sort)
  end

  it "sorts by txDateDesc" do
    result = execute_graphql(query, variables: { "sort" => ["txDateDesc"] })
    dates = result.dig("data", "creditCardTransactions").map { |t| t["txDate"] }

    expect(dates).to eq(dates.sort.reverse)
  end

  it "combines showAnnotated: false and showCredits: false" do
    result = execute_graphql(query, variables: { "showAnnotated" => false, "showCredits" => false })
    ids = transaction_ids(result)

    expect(ids).not_to include(credit_card_transactions(:annotated_debit).id)
    expect(ids).not_to include(credit_card_transactions(:recent_credit).id)
    expect(ids).to include(credit_card_transactions(:recent_debit).id)
  end
end
