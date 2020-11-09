module Types
  class NoteType < Types::BaseObject
    field :id, ID, null: false
    field :credit_card_transaction_id, Integer, null: true
    field :detail, String, null: true
  end
end
