# frozen_string_literal: true

class CreditCardTransaction < ApplicationRecord
  has_one :debit_specific_credit, foreign_key: :debit_id
  has_one :credit_transaction, through: :debit_specific_credit, source: :credit

  has_one :note

  scope :debit, -> { where(credit: nil) }
  scope :credit, -> { where(debit: nil) }

  def self.without_credit
    left_outer_joins(:debit_specific_credit).where(credits_debits: { debit_id: nil })
  end

  def amount
    debit || credit
  end

  def debit?
    credit.nil? && debit.present?
  end

  def credit?
    debit.nil? && credit.present?
  end

  def to_s
    "#{id}-#{tx_date}-$#{amount}-#{details}"
  end
end

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
