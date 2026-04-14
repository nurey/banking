module Types
  class QueryType < Types::BaseObject
    # Add root-level fields here.
    # They will be entry points for queries on your schema.

    field :credit_card_transactions, [Types::CreditCardTransactionType], null: false do
      description 'Returns a list of credit card transactions'
      argument :sort, [Types::Enum::CreditCardTransactionSort], required: false, default_value: []
      argument :show_annotated, Boolean, required: false, default_value: true
      argument :show_credits, Boolean, required: false, default_value: true
    end

    def credit_card_transactions(**options)
      scope = context[:current_user].credit_card_transactions.where(tx_date: 12.months.ago..).order(options[:sort])
      scope = scope.without_notes unless options[:show_annotated]
      scope = scope.debit unless options[:show_credits]

      scope
    end

    field :notes, [Types::NoteType], null: false,
      description: 'Returns a list of notes'

    def notes
      Note.joins(:credit_card_transaction)
          .where(credit_card_transactions: { user_id: context[:current_user].id })
    end

    field :flinks_connections, [Types::FlinksConnectionType], null: false,
      connection: false,
      description: 'Returns the current user\'s Flinks connections'

    def flinks_connections
      context[:current_user].flinks_connections
    end
  end
end
