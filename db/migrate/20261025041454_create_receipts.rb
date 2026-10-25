# Paper receipts scanned by the receipt-scanner iPhone app (its PLAN.md has the
# full design). The phone runs OCR and uploads the raw capture; the server parses
# it. Everything needed to parse a receipt again lives on the row (`raw_text`,
# `ocr_lines`, and the page images in Active Storage), so a better parser can
# re-run over old receipts. `parsed` keeps the parser's untouched output apart
# from the human-corrected columns.
#
# `capture_id` is generated on the phone, once per scan. It's the idempotency key
# for upload retries and the only identifier the API uses; `id` stays internal.
#
# Money is integer cents, like credit_card_transactions.debit/credit. There's no
# link to credit_card_transactions yet: it gets designed when matching is built,
# and adding it then is a cheap migration.
class CreateReceipts < ActiveRecord::Migration[8.1]
  def change
    create_table :receipts do |t|
      t.uuid :capture_id, null: false                # device-generated; idempotency key
      t.text :parse_status, null: false
      t.text :review_reasons, array: true, null: false, default: []
      t.integer :parser_version

      t.text :merchant
      t.date :purchased_on                          # always set when a date was found
      t.datetime :purchased_at                      # only when a time was found too
      t.text :currency, null: false, default: "CAD"
      t.integer :subtotal                           # cents
      t.integer :tax                                # cents, sum of taxes[]
      t.jsonb :taxes, null: false, default: []      # [{label, rate, amount}]
      t.integer :total                              # cents
      t.text :card_last_four

      t.text :raw_text, null: false
      t.jsonb :ocr_lines, null: false
      t.jsonb :parsed, null: false, default: {}     # parser's untouched output, kept apart from human edits
      t.jsonb :metadata, null: false, default: {}   # ocr settings, device, app version

      t.datetime :captured_at
      t.datetime :confirmed_at
      t.timestamps default: -> { "CURRENT_TIMESTAMP" }
    end

    add_index :receipts, :capture_id, unique: true
    add_index :receipts, :parse_status
    add_index :receipts, :purchased_on
    add_index :receipts, [ :created_at, :id ]         # list ordering and cursor paging
    add_check_constraint :receipts,
      "parse_status IN ('parsed', 'needs_review', 'confirmed', 'failed')",
      name: "receipts_parse_status_check"

    # Not `line_items`: this database also holds card transactions, where a bare
    # line_items would be ambiguous.
    create_table :receipt_line_items do |t|
      t.references :receipt, null: false, foreign_key: { on_delete: :cascade }
      t.integer :position, null: false
      t.text :description, null: false
      t.decimal :qty, precision: 10, scale: 3       # weights such as 1.234 kg
      t.integer :unit_price                         # cents
      t.integer :line_total, null: false            # cents; negative for discounts and coupons
      t.text :sku
    end
    add_index :receipt_line_items, [ :receipt_id, :position ], unique: true
  end
end
