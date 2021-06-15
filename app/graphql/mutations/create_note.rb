module Mutations
  class CreateNote < BaseMutation
    null true

    argument :detail, String, required: true
    argument :credit_card_transaction_id, ID, required: true

    field :note, Types::NoteType, null: true
    field :errors, [String], null: false

    def resolve(detail:, credit_card_transaction_id:)
      note = Note.new(detail: detail, credit_card_transaction_id: credit_card_transaction_id)
      if note.save
        {
          note: note,
          errors: []
        }
      else
        {
          note: nil,
          errors: note.errors.full_messages
        }
      end
    end
  end
end
