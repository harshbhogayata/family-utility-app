# 094 — Health summary PDF

**Section:** 9. Personal records
**Phase:** 3
**Priority score:** 50 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** [088 Medicine reminders with pill stock](./088-medicine-reminders-with-pill-stock.md), [089 BP and sugar logs](./089-bp-and-sugar-logs.md), [091 Reports vault](./091-reports-vault.md)

## What the person gets
One page for a new doctor: conditions, medicines, recent readings.

## Acceptance criteria
- [ ] Generated from records; chosen sections only; share as PDF
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/094_health-summary-pdf/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
