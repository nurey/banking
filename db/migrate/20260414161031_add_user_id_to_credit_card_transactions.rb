class AddUserIdToCreditCardTransactions < ActiveRecord::Migration[8.1]
  def up
    add_reference :credit_card_transactions, :user, null: true, foreign_key: true

    if CreditCardTransaction.unscoped.exists?
      password = ENV.fetch("ADMIN_PASSWORD") { raise "Set ADMIN_PASSWORD env var to run this migration" }
      digest = BCrypt::Password.create(password)
      execute <<~SQL
        INSERT INTO users (email_address, password_digest, created_at, updated_at)
        VALUES ('ilia@lobsanov.com', '#{digest}', NOW(), NOW())
        ON CONFLICT (email_address) DO NOTHING
      SQL
      execute <<~SQL
        UPDATE credit_card_transactions
        SET user_id = (SELECT id FROM users WHERE email_address = 'ilia@lobsanov.com')
        WHERE user_id IS NULL
      SQL
    end

    change_column_null :credit_card_transactions, :user_id, false

    remove_index :credit_card_transactions, name: :credit_card_transactions_debits_unique_key
    remove_index :credit_card_transactions, name: :credit_card_transactions_credits_unique_key

    add_index :credit_card_transactions, [:user_id, :tx_date, :details, :debit],
      unique: true, where: "credit IS NULL",
      name: "credit_card_transactions_debits_unique_key"
    add_index :credit_card_transactions, [:user_id, :tx_date, :details, :credit],
      unique: true, where: "debit IS NULL",
      name: "credit_card_transactions_credits_unique_key"
  end

  def down
    remove_index :credit_card_transactions, name: :credit_card_transactions_debits_unique_key
    remove_index :credit_card_transactions, name: :credit_card_transactions_credits_unique_key

    add_index :credit_card_transactions, [:tx_date, :details, :debit],
      unique: true, where: "credit IS NULL",
      name: "credit_card_transactions_debits_unique_key"
    add_index :credit_card_transactions, [:tx_date, :details, :credit],
      unique: true, where: "debit IS NULL",
      name: "credit_card_transactions_credits_unique_key"

    remove_reference :credit_card_transactions, :user
  end
end
