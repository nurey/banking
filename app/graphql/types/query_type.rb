module Types
  class QueryType < Types::BaseObject
    # Add root-level fields here.
    # They will be entry points for queries on your schema.

    field :credit_card_transactions, [Types::CreditCardTransactionType], null: false do
      description 'Returns a list of credit card transactions'
      argument :sort, [Types::Enum::CreditCardTransactionSort], required: false, default_value: []
      argument :show_annotated, Boolean, required: false, default_value: true
    end

    def credit_card_transactions(**options)
      scope = CreditCardTransaction.all.order(options[:sort])
      unless options[:show_annotated]
        scope = scope.without_notes
      end

      scope
    end

    field :notes, [Types::NoteType], null: false,
      description: 'Returns a list of notes'

    def notes
      Note.all
    end
  end
end
