class AddUniqueKeyOnCreditCardTransactions < ActiveRecord::Migration[6.1]
  def change
    add_index :credit_card_transactions, [ :tx_date, :details, :debit ], unique: true, where: 'credit IS NULL', name: 'credit_card_transactions_debits_unique_key'
    add_index :credit_card_transactions, [ :tx_date, :details, :credit ], unique: true, where: 'debit IS NULL', name: 'credit_card_transactions_credits_unique_key'
  end
end
