# frozen_string_literal: true

require "rails_helper"

RSpec.describe "updateCreditCardTransaction mutation" do
  fixtures :credit_card_transactions, :notes

  let(:mutation) do
    <<~GQL
      mutation($id: ID!, $noteDetail: String!, $noteId: ID) {
        updateCreditCardTransaction(id: $id, noteDetail: $noteDetail, noteId: $noteId) {
          creditCardTransaction {
            id
            note {
              id
              detail
            }
          }
          errors
        }
      }
    GQL
  end

  it "creates a note on a transaction that has none" do
    tx = credit_card_transactions(:recent_debit)
    result = execute_graphql(mutation, variables: {
      "id" => tx.id.to_s,
      "noteDetail" => "New note via update"
    })
    tx_data = result.dig("data", "updateCreditCardTransaction", "creditCardTransaction")

    expect(tx_data["note"]["detail"]).to eq("New note via update")
    expect(result.dig("data", "updateCreditCardTransaction", "errors")).to be_empty
  end

  it "updates an existing note when noteId is provided" do
    tx = credit_card_transactions(:annotated_debit)
    note = notes(:annotated_note)
    result = execute_graphql(mutation, variables: {
      "id" => tx.id.to_s,
      "noteDetail" => "Updated via mutation",
      "noteId" => note.id.to_s
    })
    tx_data = result.dig("data", "updateCreditCardTransaction", "creditCardTransaction")

    expect(tx_data["note"]["detail"]).to eq("Updated via mutation")
    expect(result.dig("data", "updateCreditCardTransaction", "errors")).to be_empty
  end

  it "raises an error for a non-existent transaction ID" do
    expect {
      execute_graphql(mutation, variables: {
        "id" => "0",
        "noteDetail" => "Should fail"
      })
    }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "persists note changes in the database" do
    tx = credit_card_transactions(:recent_debit)
    execute_graphql(mutation, variables: {
      "id" => tx.id.to_s,
      "noteDetail" => "Persisted via update"
    })

    tx.reload
    expect(tx.note).to be_present
    expect(tx.note.detail).to eq("Persisted via update")
  end
end
