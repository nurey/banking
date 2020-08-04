class CreditCardTransactionsController < ApplicationController
  def index
    transactions = CreditCardTransaction.order(tx_date: :desc).limit(100)
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
end
