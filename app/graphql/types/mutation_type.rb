module Types
  class MutationType < Types::BaseObject
    field :create_note, mutation: Mutations::CreateNote
    field :update_credit_card_transaction, mutation: Mutations::UpdateCreditCardTransaction
  end
end
