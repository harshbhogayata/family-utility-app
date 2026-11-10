# 087 — Loan tracker

**Section:** 9. Personal records
**Phase:** 3
**Priority score:** 80 / 125 (often × matters × reach)
**Status:** done ae423fc
**Depends on:** [083 Bill reminders](./083-bill-reminders.md)

## What the person gets
Balance, EMI dates, and the effect of a prepayment.

## Acceptance criteria
- [x] Amortisation schedule; prepayment what-if; EMI reminders
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/087_loan-tracker/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
