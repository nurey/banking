# Rogers exports 15 columns where the CIBC/Costco exports have 5. Rather than
# widen the table once per extra field, `category` gets a first-class column
# (it is the only one worth filtering and grouping on) and everything else
# Rogers sends — posted date, reference number, merchant location, rewards —
# lands in `metadata`.
#
# `metadata` is NOT NULL because every importer stamps the export a row came
# from as `source`, including the CIBC and Costco ones that have nothing else
# to contribute. `category` stays nullable: CIBC sends no categories, and
# Rogers itself leaves it blank on payments and credits.
#
# Neither column participates in the dedup unique indexes, so importing is
# still keyed on (tx_date, details, debit/credit, card_number) exactly as before.
class AddCategoryAndMetadataToCreditCardTransactions < ActiveRecord::Migration[8.1]
  def up
    add_column :credit_card_transactions, :category, :text
    add_column :credit_card_transactions, :metadata, :jsonb

    # Existing rows predate the column, and the card number is the only record
    # of where they came from: 4500/4505 are the CIBC Visas, 5268 the Costco
    # Mastercards, and the rest are the two fully masked Rogers cards. Verified
    # against production -- every row matches one of the three, none are NULL.
    # Rogers rows pick up the rest of their metadata when the CSVs are
    # re-imported via `make backfill_rogers`.
    execute <<~SQL
      UPDATE credit_card_transactions
      SET metadata = jsonb_build_object('source',
            CASE
              WHEN card_number LIKE '5268%' THEN 'costco'
              WHEN card_number LIKE '4500%' OR card_number LIKE '4505%' THEN 'cibc'
              ELSE 'rogers'
            END)
    SQL

    change_column_null :credit_card_transactions, :metadata, false
  end

  def down
    remove_column :credit_card_transactions, :metadata
    remove_column :credit_card_transactions, :category
  end
end
