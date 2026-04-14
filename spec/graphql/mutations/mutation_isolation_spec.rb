# frozen_string_literal: true

require "rails_helper"

RSpec.describe "mutation isolation" do
  fixtures :users, :credit_card_transactions, :notes

  describe "updateCreditCardTransaction" do
    let(:mutation) do
      <<~GQL
        mutation($id: ID!, $noteDetail: String!) {
          updateCreditCardTransaction(id: $id, noteDetail: $noteDetail) {
            creditCardTransaction { id }
            errors
          }
        }
      GQL
    end

    it "cannot update another user's transaction" do
      bob = users(:bob)
      alice_tx = credit_card_transactions(:recent_debit)  # belongs to alice

      expect {
        execute_graphql(mutation,
          variables: { "id" => alice_tx.id.to_s, "noteDetail" => "hacked" },
          context: { current_user: bob })
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "createNote" do
    let(:mutation) do
      <<~GQL
        mutation($creditCardTransactionId: ID!, $detail: String!) {
          createNote(creditCardTransactionId: $creditCardTransactionId, detail: $detail) {
            note { id detail }
            errors
          }
        }
      GQL
    end

    it "cannot annotate another user's transaction" do
      bob = users(:bob)
      alice_tx = credit_card_transactions(:recent_debit)

      expect {
        execute_graphql(mutation,
          variables: { "creditCardTransactionId" => alice_tx.id.to_s, "detail" => "hacked" },
          context: { current_user: bob })
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
