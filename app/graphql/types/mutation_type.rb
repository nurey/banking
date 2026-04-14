module Types
  class MutationType < Types::BaseObject
    field :create_note, mutation: Mutations::CreateNote
    field :update_credit_card_transaction, mutation: Mutations::UpdateCreditCardTransaction
    field :create_flinks_connection, mutation: Mutations::CreateFlinksConnection
    field :delete_flinks_connection, mutation: Mutations::DeleteFlinksConnection
  end
end
