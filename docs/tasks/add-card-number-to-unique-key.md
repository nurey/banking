# Task: Add `card_number` to the transaction dedup unique key

**Status:** Not started — investigated and recommended, not yet implemented.
**Priority:** Low (correctness insurance; no active bug — see evidence).
**Created:** 2026-07-21
**Owning app:** this repo (`~/Devel/banking`). Imports are performed by the
separate `cibc-visa-import` tooling repo, which loads into this app's
`credit_card_transactions` table via `ON CONFLICT DO NOTHING`.

## Goal

Add `card_number` to the two partial unique indexes on
`credit_card_transactions` so a transaction is de-duplicated **per card**
rather than globally.

Current indexes (`db/schema.rb`):

```
credit_card_transactions_credits_unique_key  UNIQUE (tx_date, details, credit) WHERE debit  IS NULL
credit_card_transactions_debits_unique_key   UNIQUE (tx_date, details, debit)  WHERE credit IS NULL
```

`card_number` is deliberately **not** in the key. Consequence: two different
cards with a genuinely distinct transaction sharing the same
`(tx_date, details, amount)` collide, and the second is silently dropped on
import. Plausible for generic descriptions (`PAYMENT THANK YOU`, `CASHBACK`, gas
at the same station/price on the same day).

## Why this is safe (evidence gathered 2026-07-21)

- **Cross-card collisions in history: 0** — across ~9,770 source rows / 6,768
  distinct keys (CIBC Visa + CIBC Costco Mastercard + Rogers). The change alters
  *no* existing behavior; it only closes a future hole.
- **`card_number` is always populated** — 0 null/blank across 6,815 live rows.
- **Masked numbers are stable** — every last-4 maps 1:1 to a single mask, so
  adding `card_number` does **not** break re-import dedup (which depends on the
  mask being byte-identical across exports — it is).
- Every existing row is already unique on the *narrower* key, therefore
  automatically unique on the *wider* key → **no data cleanup needed**; the new
  indexes build without conflict.

## Implementation (Rails migration)

Follow the existing convention in
`db/migrate/20260322222234_convert_debit_credit_to_integer_cents.rb`, which
swaps these same two indexes inline (plain `remove_index`/`add_index`, no
`algorithm: :concurrently` — the table is small, ~6.8k rows, so a brief lock is
fine and matches repo style). Keep the **same index names**.

```ruby
class AddCardNumberToCreditCardTransactionUniqueKeys < ActiveRecord::Migration[8.1]
  def up
    remove_index :credit_card_transactions, name: :credit_card_transactions_debits_unique_key
    remove_index :credit_card_transactions, name: :credit_card_transactions_credits_unique_key

    add_index :credit_card_transactions, [:tx_date, :details, :debit, :card_number],
      unique: true, where: "credit IS NULL",
      name: "credit_card_transactions_debits_unique_key"
    add_index :credit_card_transactions, [:tx_date, :details, :credit, :card_number],
      unique: true, where: "debit IS NULL",
      name: "credit_card_transactions_credits_unique_key"
  end

  def down
    remove_index :credit_card_transactions, name: :credit_card_transactions_debits_unique_key
    remove_index :credit_card_transactions, name: :credit_card_transactions_credits_unique_key

    add_index :credit_card_transactions, [:tx_date, :details, :debit],
      unique: true, where: "credit IS NULL",
      name: "credit_card_transactions_debits_unique_key"
    add_index :credit_card_transactions, [:tx_date, :details, :credit],
      unique: true, where: "debit IS NULL",
      name: "credit_card_transactions_credits_unique_key"
  end
end
```

Generate with `bin/rails g migration AddCardNumberToCreditCardTransactionUniqueKeys`
(then paste the body), run `bin/rails db:migrate`, and commit the updated
`db/schema.rb`.

## No change needed in the import tooling

`cibc-visa-import`'s `import.sql` / `import_rogers.sql` use
`ON CONFLICT DO NOTHING` with **no explicit conflict target**, so they catch
whichever unique index applies and keep working unchanged after the key widens.

## Verification

1. `bin/rails db:migrate`; confirm `db/schema.rb` shows both indexes now
   include `card_number`.
2. In `cibc-visa-import`, re-run an already-imported file
   (`make costco CSV_SUFFIX=20260721`) → expect `INSERT 0 0`, proving re-import
   dedup still holds under the wider key.
3. Migration itself changes no rows: `credit_card_transactions` count unchanged.

## Decision note

Recommended as cheap insurance — downside is effectively nil for this data — but
it fixes no observed problem. Deferring is defensible given a spotless
9,770-row track record.
