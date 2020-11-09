module Types
  class CreditCardTransactionType < Types::BaseObject
    field :id, ID, null: false
    field :tx_date, GraphQL::Types::ISO8601Date, null: true
    field :details, String, null: true
    field :debit, Float, null: true
    field :credit, Float, null: true
    field :card_number, String, null: true
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
    field :note, Types::NoteType, null: true

    def note
      Loaders::HasOneLoader.for(Note, :credit_card_transaction_id).load(object.id)
    end
  end
end
