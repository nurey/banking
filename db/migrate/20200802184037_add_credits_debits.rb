class AddCreditsDebits < ActiveRecord::Migration[6.0]
  def change
    create_table :credits_debits do |t|
      t.bigint :credit_id, index: { unique: true }
      t.bigint :debit_id, index: { unique: true }
      t.text :details
      t.timestamps default: -> { 'CURRENT_TIMESTAMP' }
    end
  end
end
