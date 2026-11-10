# 100 — Loyalty cards

**Section:** 9. Personal records
**Phase:** 3
**Priority score:** 64 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** [051 QR scanner](./051-qr-scanner.md)

## What the person gets
Barcodes scanned once, shown at the till.

## Acceptance criteria
- [ ] Scan a card; full-brightness barcode screen; works offline
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/100_loyalty-cards/`.
- Scanning reuses 051's on-device `mobile_scanner` with all formats; cards live on the family store (`loyalty_cards`). Barcodes are redrawn with the pure-Dart `barcode` / `barcode_widget` packages (Code 93 and UPC-E are redrawn as Code 128). Full brightness reuses 130's window-only brightness channel and puts the old level back on leaving.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
