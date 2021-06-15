# frozen_string_literal: true

class CreditCardTransactionsController < ApplicationController
  def index
    transactions = CreditCardTransaction.includes(:credit_transaction).order(tx_date: :desc).limit(1000)
    render json: CreditCardTransactionSerializer.new(transactions).serializable_hash
  end

  def debits
    debits = CreditCardTransaction.debit.order(tx_date: :desc).limit(100)

    render json: CreditCardTransactionSerializer.new(debits).serializable_hash
  end

  def debits_outstanding
    debits = CreditCardTransaction.debit.without_credit.order(tx_date: :desc).limit(100)

    render json: CreditCardTransactionSerializer.new(debits).serializable_hash
  end

  def debits_with_credits
    debits = CreditCardTransaction.debit.with_credit.includes(:credit_transaction).order(tx_date: :desc).limit(100)

    render json: CreditCardTransactionSerializer.new(debits, { include: [:credit_transaction] }).serializable_hash
  end
end
