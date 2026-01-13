module Mutations
  class UpdateCreditCardTransaction < BaseMutation
    null true

    argument :note_detail, String, required: true
    argument :note_id, ID, required: false
    argument :id, ID, required: true

    field :credit_card_transaction, Types::CreditCardTransactionType, null: true
    field :errors, [ String ], null: false

    def resolve(note_detail:, note_id: nil, id:)
      tx = CreditCardTransaction.find_by!(id: id)
      if tx.update(note_attributes: { detail: note_detail, id: note_id })
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
