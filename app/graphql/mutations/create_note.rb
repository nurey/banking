module Mutations
  class CreateNote < BaseMutation
    null true

    argument :detail, String, required: true
    argument :credit_card_transaction_id, ID, required: true

    field :note, Types::NoteType, null: true
    field :errors, [ String ], null: false

    def resolve(detail:, credit_card_transaction_id:)
      Note.upsert(
        {
          detail: detail,
          credit_card_transaction_id: credit_card_transaction_id
        },
        unique_by: :credit_card_transaction_id
      )
      if (note = Note.find_by(credit_card_transaction_id: credit_card_transaction_id))
        {
          note: note,
          errors: []
        }
      else
        {
          note: nil,
          errors: "Something went wrong"
        }
      end
    end
  end
end
