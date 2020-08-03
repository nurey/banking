class CreditCardTransaction < ApplicationRecord
  has_one :debit_specific_credit, foreign_key: :debit_id
  has_one :credit_transaction, through: :debit_specific_credit, source: :credit

  scope :debit, -> { where(credit: nil) }
  scope :credit, -> { where(debit: nil) }

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
