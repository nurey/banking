class AddCardNumberToCreditCardTransactionUniqueKeys < ActiveRecord::Migration[8.1]
  def change
    remove_index :credit_card_transactions, [:tx_date, :details, :debit],
      unique: true, where: "credit IS NULL",
      name: "credit_card_transactions_debits_unique_key"
    remove_index :credit_card_transactions, [:tx_date, :details, :credit],
      unique: true, where: "debit IS NULL",
      name: "credit_card_transactions_credits_unique_key"

    add_index :credit_card_transactions, [:tx_date, :details, :debit, :card_number],
      unique: true, where: "credit IS NULL",
      name: "credit_card_transactions_debits_unique_key"
    add_index :credit_card_transactions, [:tx_date, :details, :credit, :card_number],
      unique: true, where: "debit IS NULL",
      name: "credit_card_transactions_credits_unique_key"
  end
end
