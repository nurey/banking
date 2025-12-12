# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_12_12_222741) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "credit_card_transactions", force: :cascade do |t|
    t.date "tx_date"
    t.text "details"
    t.decimal "debit"
    t.decimal "credit"
    t.text "card_number"
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["tx_date", "details", "credit"], name: "credit_card_transactions_credits_unique_key", unique: true, where: "(debit IS NULL)"
    t.index ["tx_date", "details", "debit"], name: "credit_card_transactions_debits_unique_key", unique: true, where: "(credit IS NULL)"
  end

  create_table "credits_debits", force: :cascade do |t|
    t.bigint "credit_id"
    t.bigint "debit_id"
    t.text "details"
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["credit_id"], name: "index_credits_debits_on_credit_id", unique: true
    t.index ["debit_id"], name: "index_credits_debits_on_debit_id", unique: true
  end

  create_table "notes", force: :cascade do |t|
    t.bigint "credit_card_transaction_id"
    t.text "detail"
    t.index ["credit_card_transaction_id"], name: "index_notes_on_credit_card_transaction_id", unique: true
  end

  add_foreign_key "notes", "credit_card_transactions"
end
