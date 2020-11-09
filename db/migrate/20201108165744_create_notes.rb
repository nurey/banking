class CreateNotes < ActiveRecord::Migration[6.0]
  def change
    create_table :notes do |t|
      t.belongs_to :credit_card_transaction
      t.text :detail
    end
  end
end
