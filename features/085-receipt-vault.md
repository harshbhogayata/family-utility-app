# 085 — Receipt vault

**Section:** 9. Personal records
**Phase:** 3
**Priority score:** 64 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [050 Receipt scan into the receipt vault](./050-receipt-scan-into-the-receipt-vault.md), [114 One search](./114-one-search.md)

## What the person gets
Scanned receipts tagged and searchable by shop or amount.

## Acceptance criteria
- [ ] Full-text search over OCR; link to an expense and a warranty
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/085_receipt-vault/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
