module Types
  module Enum
    class CreditCardTransactionSort < Types::BaseEnum
      value 'txDateAsc', value: [:tx_date, :asc]
      value 'txDateDesc', value: [:tx_date, :desc]
    end
  end
end
