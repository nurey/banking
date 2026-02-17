# frozen_string_literal: true

require "rails_helper"

RSpec.describe "notes query" do
  fixtures :credit_card_transactions, :notes

  let(:query) do
    <<~GQL
      {
        notes {
          id
          detail
          creditCardTransactionId
        }
      }
    GQL
  end

  it "returns all notes with correct fields" do
    result = execute_graphql(query)
    notes_data = result.dig("data", "notes")
    note = notes(:annotated_note)

    expect(notes_data.length).to eq(1)
    expect(notes_data.first["id"]).to eq(note.id.to_s)
    expect(notes_data.first["detail"]).to eq("Business dinner expense")
  end

  it "returns empty array when no notes exist" do
    Note.delete_all
    result = execute_graphql(query)
    notes_data = result.dig("data", "notes")

    expect(notes_data).to eq([])
  end

  it "includes creditCardTransactionId" do
    result = execute_graphql(query)
    note_data = result.dig("data", "notes").first

    expect(note_data["creditCardTransactionId"]).to eq(credit_card_transactions(:annotated_debit).id)
  end
end
