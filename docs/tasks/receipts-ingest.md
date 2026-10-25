# Task: Receipt ingest API for the receipt-scanner iPhone app

**Status:** Built on branch `receipts-ingest`; not yet deployed (see "Deploy" below).
**Created:** 2026-10-25
**Owning app:** this repo. The client is `~/Devel/receipt-scanner` (SwiftUI, iPhone 13 mini). Its
`PLAN.md` is the full design; this file records what was built here and how to ship it.

## Goal

Scan a paper receipt on the phone, run OCR there, and archive it in this database: the page images,
the raw OCR, and the parsed merchant, date, items, taxes, and total. Every receipt keeps its raw
capture, so it can be re-parsed when the parser improves.

## What was built

- **Active Storage is back** (`14ed9a2` reverted) with the Disk service at `storage/`
  (`/rails/storage`, a Kamal volume on optiplex). Its `/rails/active_storage/*` routes are off
  (`draw_routes = false`); images are only served behind the API token. Active Job is loaded on the
  default `:async` adapter for Active Storage's analyze and purge jobs. No libvips: the phone uploads
  its own thumbnail.
- **Tables:** `receipts` and `receipt_line_items` (`20261025041454_create_receipts.rb`). Money is
  integer cents. `capture_id` (a UUID made on the phone) is the idempotency key and the only identifier
  the API uses.
- **Parser:** `ReceiptParser` (`app/models/receipt_parser/`) is a pipeline of eight step commands over
  an immutable `Context`, with a per-step trace stored in `receipts.parsed`. `ReceiptValidator` sets
  `needs_review` and the `review_reasons`. `ReceiptParser::VERSION` is 1.
- **API:** `/api/receipts` (`Api::ReceiptsController`, `Api::ReceiptImagesController`): multipart
  create, index with a cursor, show, PATCH to correct and confirm, page images, thumbnail. Auth is one
  bearer token, `RECEIPTS_API_TOKEN`, failing closed when unset. The contract examples live in
  receipt-scanner's `contract/` and are vendored in `spec/fixtures/contract/`
  (`spec/contract_sync_spec.rb` catches drift).
- **Rake:** `receipts:reparse` (outdated, unconfirmed receipts), `"receipts:reparse[<id or capture_id>]"`
  (one receipt; `FORCE=1` rewrites only a confirmed receipt's `parsed`), and
  `receipts:bench DIR=…` (development: scores `ocr-bench` output per preprocessing variant).
- **Logs:** `:receipt`, `:raw_text`, and `:ocr_lines` are in `filter_parameters`, because Rails logs
  parameters before the token is checked.

## Deploy

Nothing below has been done yet. In order:

1. **Token.** `openssl rand -hex 32`, stored in 1Password `Private/Budgetr` as `RECEIPTS_API_TOKEN`.
   `.kamal/secrets-common` now fetches that field for **every** destination, so `kamal deploy` (optiplex
   and production) fails until the field exists. Put the same token in the app's Settings.
2. **Pre-flight checks on the optiplex database** (read-only):
   ```sh
   PGOPTIONS='-c default_transaction_read_only=on' psql -h 10.0.0.218 -U ilia -d banking_production \
     -c "select version from schema_migrations where version like '20251212%';" \
     -c "select to_regclass('active_storage_blobs'), to_regclass('receipts');"
   ```
   Expect the three `20251212…` rows and two NULLs. If the Active Storage tables already exist,
   `create_active_storage_tables` will fail on `db:prepare`; mark it as run instead.
3. **Homelab** (branch `receipts-serve` in `~/Devel/homelab`): creates `/var/lib/budgetr/storage`
   (`1000:1000`, `0750`), adds it to the nightly backup, and adds the `tailscale serve --https=8443`
   entry for `/api` only. Apply it **before** the deploy, or Docker creates the volume directory as
   root and the container (uid 1000) can't write to it.
4. **Deploy** this branch to optiplex: `kamal deploy`. The entrypoint's `db:prepare` runs the two new
   migrations. Production (`-d production`) can follow at any time: it gets the tables but no token,
   so its endpoint answers 401.
5. **Check from a tailnet device:**
   ```sh
   curl -i https://optiplex.tail99a066.ts.net:8443/api/receipts            # 401 from Rails
   curl -i https://optiplex.tail99a066.ts.net:8443/graphql                 # 404 from Tailscale, not Rails
   curl -i https://optiplex.tail99a066.ts.net:8443/up                      # 404 from Tailscale
   curl -i -H "Authorization: Bearer $TOKEN" \
     -F "receipt=@contract/create_receipt.request.json;type=application/json" \
     -F "images[]=@spec/fixtures/files/page.jpg;type=image/jpeg" \
     https://optiplex.tail99a066.ts.net:8443/api/receipts                   # 201
   ```
   The `curl -F receipt=@…` form sends a filename with the JSON part; the controller reads either form.

## Notes

- `CORS_ORIGINS` is now `http://budgetr.lan` on optiplex (it was unset, so `*`). Check the web frontend
  at `http://budgetr.lan` still works after the deploy.
- Thruster's `MAX_REQUEST_BODY` defaults to 0 (no limit), so only kamal-proxy's 70 MB cap applies.
  Thruster keeps its own state in `storage/thruster`, which is now on the volume; that's harmless.
- Rails parses the multipart body (to log its parameters) before the token is checked, so anything on
  the home LAN can make the server buffer up to 70 MB without a token. Accepted for a single-user box.
