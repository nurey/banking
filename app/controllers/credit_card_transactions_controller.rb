# rbs_inline: enabled
# frozen_string_literal: true

class CreditCardTransactionsController < ApplicationController
  # @rbs return: void
  def index
    transactions = user_transactions.includes(:credit_transaction).order(tx_date: :desc).limit(1000)
    render json: CreditCardTransactionSerializer.new(transactions).serializable_hash
  end

  # @rbs return: void
  def debits
    debits = user_transactions.debit.order(tx_date: :desc).limit(100)
    render json: CreditCardTransactionSerializer.new(debits).serializable_hash
  end

  # @rbs return: void
  def debits_outstanding
    debits = user_transactions.debit.without_credit.order(tx_date: :desc).limit(100)
    render json: CreditCardTransactionSerializer.new(debits).serializable_hash
  end

  # @rbs return: void
  def debits_with_credits
    debits = user_transactions.debit.with_credit.includes(:credit_transaction).order(tx_date: :desc).limit(100)
    render json: CreditCardTransactionSerializer.new(debits, { include: [:credit_transaction] }).serializable_hash
  end

  private

  def user_transactions
    Current.user.credit_card_transactions
  end
end
