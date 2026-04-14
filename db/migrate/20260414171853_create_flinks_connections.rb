class CreateFlinksConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :flinks_connections do |t|
      t.references :user, null: false, foreign_key: true
      t.string :institution, null: false
      t.string :login_id, null: false
      t.string :request_id
      t.datetime :last_synced_at
      t.string :status, null: false, default: "active"

      t.timestamps
    end

    add_index :flinks_connections, [:user_id, :institution], unique: true
  end
end
