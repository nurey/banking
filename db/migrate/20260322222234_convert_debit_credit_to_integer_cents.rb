class ConvertDebitCreditToIntegerCents < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE credit_card_transactions
      SET debit = ROUND(debit * 100),
          credit = ROUND(credit * 100)
    SQL

    remove_index :credit_card_transactions, name: :credit_card_transactions_debits_unique_key
    remove_index :credit_card_transactions, name: :credit_card_transactions_credits_unique_key

    change_column :credit_card_transactions, :debit, :integer
    change_column :credit_card_transactions, :credit, :integer

    add_index :credit_card_transactions, [:tx_date, :details, :debit],
      unique: true, where: "credit IS NULL",
      name: "credit_card_transactions_debits_unique_key"
    add_index :credit_card_transactions, [:tx_date, :details, :credit],
      unique: true, where: "debit IS NULL",
      name: "credit_card_transactions_credits_unique_key"
  end

  def down
    remove_index :credit_card_transactions, name: :credit_card_transactions_debits_unique_key
    remove_index :credit_card_transactions, name: :credit_card_transactions_credits_unique_key

    change_column :credit_card_transactions, :debit, :decimal
    change_column :credit_card_transactions, :credit, :decimal

    execute <<~SQL
      UPDATE credit_card_transactions
      SET debit = debit / 100.0,
          credit = credit / 100.0
    SQL

    add_index :credit_card_transactions, [:tx_date, :details, :debit],
      unique: true, where: "credit IS NULL",
      name: "credit_card_transactions_debits_unique_key"
    add_index :credit_card_transactions, [:tx_date, :details, :credit],
      unique: true, where: "debit IS NULL",
      name: "credit_card_transactions_credits_unique_key"
  end
end
