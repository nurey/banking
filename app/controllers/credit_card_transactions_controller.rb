class CreditCardTransactionsController < ApplicationController
  def index
    transactions = CreditCardTransaction.order(tx_date: :desc).limit(100)
    render json: CreditCardTransactionSerializer.new(transactions).serializable_hash
  end

  def debits
    debits = CreditCardTransaction.debit.order(tx_date: :desc).limit(100)
    # debits.each do |debit|
    #   credits_found = credits.find_all { |credit| credit.amount == debit.amount }
    #   if credits_found.length == 1
    #     Rails.logger.debug "found credit (#{credits_found.first.id}) for debit #{debit.id}"
    #     debit.credit_tx = credits_found.first.id
    #   elsif credits_found.length > 1
    #     Rails.logger.debug "found multiple credits for debit #{debit.id}"
    #   end
    # end

    render json: CreditCardTransactionSerializer.new(debits).serializable_hash
  end
end
