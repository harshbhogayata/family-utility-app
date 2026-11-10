# 091 — Reports vault

**Section:** 9. Personal records
**Phase:** 3
**Priority score:** 75 / 125 (often × matters × reach)
**Status:** done a62ca9d
**Depends on:** [056 Private vault](./056-private-vault.md), [008 OCR a scan](./008-ocr-a-scan.md)

## What the person gets
Lab reports by date, with one value charted across reports.

## Acceptance criteria
- [x] Reports stored encrypted; tag a value (e.g. HbA1c) and chart it over time
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/091_reports-vault/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
