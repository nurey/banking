class CreateCreditCardTransactions < ActiveRecord::Migration[6.0]
  def change
    create_table :credit_card_transactions do |t|
      t.date :tx_date
      t.text :details
      t.numeric :debit
      t.numeric :credit
      t.text :card_number
      t.timestamps default: -> { 'CURRENT_TIMESTAMP' }
    end
  end
end
