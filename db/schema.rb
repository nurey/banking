# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `rails
# db:schema:load`. When creating a new database, `rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2020_08_02_184037) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "cibc_visa", id: :serial, force: :cascade do |t|
    t.date "date"
    t.text "details"
    t.decimal "debit"
    t.decimal "credit"
    t.text "card_number"
  end

  create_table "credit_card_transactions", force: :cascade do |t|
    t.date "tx_date"
    t.text "details"
    t.decimal "debit"
    t.decimal "credit"
    t.text "card_number"
    t.datetime "created_at", precision: 6, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "updated_at", precision: 6, default: -> { "CURRENT_TIMESTAMP" }, null: false
  end

  create_table "credits_debits", force: :cascade do |t|
    t.bigint "credit_id"
    t.bigint "debit_id"
    t.text "details"
    t.datetime "created_at", precision: 6, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "updated_at", precision: 6, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["credit_id"], name: "index_credits_debits_on_credit_id", unique: true
    t.index ["debit_id"], name: "index_credits_debits_on_debit_id", unique: true
  end

end
