module Mutations
  class UpdateCreditCardTransaction < BaseMutation
    null true

    argument :note, String, required: true
    argument :id, ID, required: true

    field :credit_card_transaction, Types::CreditCardTransactionType, null: true
    field :errors, [String], null: false

    def resolve(note:, id:)
      tx = CreditCardTransaction.find_by!(id: id)
      tx.note.detail = note
      if tx.save
        {
          credit_card_transaction: tx,
          errors: []
        }
      else
        {
          credit_card_transaction: nil,
          errors: tx.errors.full_messages
        }
      end
    end
  end
end
