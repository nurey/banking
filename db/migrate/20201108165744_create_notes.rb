class CreateNotes < ActiveRecord::Migration[6.0]
  def change
    create_table :notes do |t|
      t.belongs_to :credit_card_transaction, foreign_key: true, index: { unique: true }
      t.text :detail
    end
  end
end
