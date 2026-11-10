# 050 — Receipt scan into the receipt vault

**Section:** 5. Scan and QR
**Phase:** 1
**Priority score:** 36 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** [047 Document scanner](./047-document-scanner.md), [008 OCR a scan](./008-ocr-a-scan.md), [085 Receipt vault](./085-receipt-vault.md)

## What the person gets
Capture a receipt and file it with amount and date.

## Acceptance criteria
- [ ] Amount and date suggested by on-device OCR; tagged to a shop; saved to the vault
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/050_receipt-scan-into-the-receipt-vault/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
