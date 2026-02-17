# frozen_string_literal: true

require "rails_helper"

RSpec.describe "createNote mutation" do
  fixtures :credit_card_transactions, :notes

  let(:mutation) do
    <<~GQL
      mutation($creditCardTransactionId: ID!, $detail: String!) {
        createNote(creditCardTransactionId: $creditCardTransactionId, detail: $detail) {
          note {
            id
            detail
            creditCardTransactionId
          }
          errors
        }
      }
    GQL
  end

  it "creates a new note for a transaction" do
    tx = credit_card_transactions(:recent_debit)
    result = execute_graphql(mutation, variables: {
      "creditCardTransactionId" => tx.id.to_s,
      "detail" => "New grocery note"
    })
    note_data = result.dig("data", "createNote", "note")

    expect(note_data["detail"]).to eq("New grocery note")
    expect(note_data["creditCardTransactionId"]).to eq(tx.id)
    expect(result.dig("data", "createNote", "errors")).to be_empty
  end

  it "upserts when a note already exists for the transaction" do
    tx = credit_card_transactions(:annotated_debit)
    result = execute_graphql(mutation, variables: {
      "creditCardTransactionId" => tx.id.to_s,
      "detail" => "Updated dinner note"
    })
    note_data = result.dig("data", "createNote", "note")

    expect(note_data["detail"]).to eq("Updated dinner note")
    expect(result.dig("data", "createNote", "errors")).to be_empty
  end

  it "persists the note in the database" do
    tx = credit_card_transactions(:recent_debit)
    execute_graphql(mutation, variables: {
      "creditCardTransactionId" => tx.id.to_s,
      "detail" => "Persisted note"
    })

    note = Note.find_by(credit_card_transaction_id: tx.id)
    expect(note).to be_present
    expect(note.detail).to eq("Persisted note")
  end
end
