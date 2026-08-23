# rbs_inline: enabled
# frozen_string_literal: true

class CreditCardTransaction < ApplicationRecord
  has_one :debit_specific_credit, foreign_key: :debit_id
  has_one :credit_transaction, through: :debit_specific_credit, source: :credit

  has_one :note
  accepts_nested_attributes_for :note

  scope :debit, -> { where(credit: nil) }

  scope :credit, -> { where(debit: nil) }

  scope :without_notes, -> do
    # exclude annotated transactions
    # TODO: empty notes should count as no notes
    left_outer_joins(:note).where(notes: { id: nil })
  end

  # @rbs return: ActiveRecord::Relation[CreditCardTransaction]
  def self.without_credit
    left_outer_joins(:debit_specific_credit).where(credits_debits: { debit_id: nil })
  end

  # @rbs return: ActiveRecord::Relation[CreditCardTransaction]
  def self.with_credit
    joins(:debit_specific_credit)
  end

  # @rbs return: Integer?
  def amount
    debit || credit
  end

  # @rbs return: bool
  def debit?
    credit.nil? && debit.present?
  end

  # @rbs return: bool
  def credit?
    debit.nil? && credit.present?
  end

  # Card numbers arrive from the bank export in a handful of shapes: a masked
  # PAN ("5268********0298", "************8525"), an unmasked PAN, or just the
  # last four digits ("1234"). They are stored verbatim because the raw value
  # participates in the dedup unique indexes, so normalize on read. Returning
  # only the last four means no readable PAN can leave the API.
  #
  # @rbs return: String?
  def card_last_four
    digits = card_number.to_s.gsub(/\D/, "")
    return nil if digits.blank?

    digits.last(4)
  end

  # @rbs return: String
  def to_s
    formatted = amount ? format('$%.2f', amount / 100.0) : '$0.00'
    "#{id}-#{tx_date}-#{formatted}-#{details}"
  end
end

# == Schema Information
#
# Table name: credit_card_transactions
#
#  id          :bigint           not null, primary key
#  card_number :text
#  credit      :integer
#  debit       :integer
#  details     :text
#  tx_date     :date
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  credit_card_transactions_credits_unique_key  (tx_date,details,credit,card_number) UNIQUE WHERE (debit IS NULL)
#  credit_card_transactions_debits_unique_key   (tx_date,details,debit,card_number) UNIQUE WHERE (credit IS NULL)
#
