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

ActiveRecord::Schema[8.1].define(version: 2026_10_25_041454) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "credit_card_transactions", force: :cascade do |t|
    t.text "card_number"
    t.text "category"
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.integer "credit"
    t.integer "debit"
    t.text "details"
    t.jsonb "metadata", null: false
    t.date "tx_date"
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["tx_date", "details", "credit", "card_number"], name: "credit_card_transactions_credits_unique_key", unique: true, where: "(debit IS NULL)"
    t.index ["tx_date", "details", "debit", "card_number"], name: "credit_card_transactions_debits_unique_key", unique: true, where: "(credit IS NULL)"
  end

  create_table "credits_debits", force: :cascade do |t|
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.bigint "credit_id"
    t.bigint "debit_id"
    t.text "details"
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["credit_id"], name: "index_credits_debits_on_credit_id", unique: true
    t.index ["debit_id"], name: "index_credits_debits_on_debit_id", unique: true
  end

  create_table "notes", force: :cascade do |t|
    t.bigint "credit_card_transaction_id"
    t.text "detail"
    t.index ["credit_card_transaction_id"], name: "index_notes_on_credit_card_transaction_id", unique: true
  end

  create_table "receipt_line_items", force: :cascade do |t|
    t.bigint "receipt_id", null: false
    t.integer "position", null: false
    t.text "description", null: false
    t.decimal "qty", precision: 10, scale: 3
    t.integer "unit_price"
    t.integer "line_total", null: false
    t.text "sku"
    t.index ["receipt_id", "position"], name: "index_receipt_line_items_on_receipt_id_and_position", unique: true
    t.index ["receipt_id"], name: "index_receipt_line_items_on_receipt_id"
  end

  create_table "receipts", force: :cascade do |t|
    t.uuid "capture_id", null: false
    t.text "parse_status", null: false
    t.text "review_reasons", default: [], null: false, array: true
    t.integer "parser_version"
    t.text "merchant"
    t.date "purchased_on"
    t.datetime "purchased_at"
    t.text "currency", default: "CAD", null: false
    t.integer "subtotal"
    t.integer "tax"
    t.jsonb "taxes", default: [], null: false
    t.integer "total"
    t.text "card_last_four"
    t.text "raw_text", null: false
    t.jsonb "ocr_lines", null: false
    t.jsonb "parsed", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "captured_at"
    t.datetime "confirmed_at"
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["capture_id"], name: "index_receipts_on_capture_id", unique: true
    t.index ["created_at", "id"], name: "index_receipts_on_created_at_and_id"
    t.index ["parse_status"], name: "index_receipts_on_parse_status"
    t.index ["purchased_on"], name: "index_receipts_on_purchased_on"
    t.check_constraint "parse_status = ANY (ARRAY['parsed'::text, 'needs_review'::text, 'confirmed'::text, 'failed'::text])", name: "receipts_parse_status_check"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "notes", "credit_card_transactions"
  add_foreign_key "receipt_line_items", "receipts", on_delete: :cascade
end
