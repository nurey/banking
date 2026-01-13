# frozen_string_literal: true

class DebitSpecificCredit < ApplicationRecord
  self.table_name = "credits_debits"

  belongs_to :credit, class_name: "CreditCardTransaction"
  belongs_to :debit, class_name: "CreditCardTransaction"
end

# == Schema Information
#
# Table name: credits_debits
#
#  id         :bigint           not null, primary key
#  details    :text
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  credit_id  :bigint
#  debit_id   :bigint
#
# Indexes
#
#  index_credits_debits_on_credit_id  (credit_id) UNIQUE
#  index_credits_debits_on_debit_id   (debit_id) UNIQUE
#
