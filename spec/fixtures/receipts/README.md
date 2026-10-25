# Parser corpus

Each receipt is a pair:

- `<name>.ocr.json`: a capture document exactly as the app uploads it (the `receipt` part of
  `POST /api/receipts`). Real ones come from the app's Settings → Debug → Export capture.
- `<name>.expected.json`: the hand-checked answer. Any of `merchant`, `purchased_on`, `purchased_at`,
  `subtotal`, `tax`, `total`, `card_last_four`, `parse_status`, and `items` (each with `description`,
  `qty`, `unit_price`, `line_total`). Only the keys present are checked.

`spec/models/receipt_parser_spec.rb` runs the parser over every pair.

`contract_*` comes from the API contract example. `synthetic_*` were rendered on the Mac and read with
Apple Vision through `ocr-bench` (receipt-scanner); they stand in until real captures are exported (M3).
