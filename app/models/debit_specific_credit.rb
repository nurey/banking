class DebitSpecificCredit < ApplicationRecord
  self.table_name = 'credits_debits'

  belongs_to :credit, class_name: 'CreditCardTransaction'
  belongs_to :debit, class_name: 'CreditCardTransaction'
end

