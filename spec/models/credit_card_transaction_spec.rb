# == Schema Information
#
# Table name: credit_card_transactions
#
#  id          :bigint           not null, primary key
#  card_number :text
#  credit      :decimal(, )
#  debit       :decimal(, )
#  details     :text
#  tx_date     :date
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  credit_card_transactions_credits_unique_key  (tx_date,details,credit) UNIQUE WHERE (debit IS NULL)
#  credit_card_transactions_debits_unique_key   (tx_date,details,debit) UNIQUE WHERE (credit IS NULL)
#
require 'rails_helper'

RSpec.describe CreditCardTransaction, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
