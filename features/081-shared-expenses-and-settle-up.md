# 081 — Shared expenses and settle-up

**Section:** 9. Personal records
**Phase:** 3
**Priority score:** 80 / 125 (often × matters × reach)
**Status:** done ec554bd
**Depends on:** [080 Expense tracker](./080-expense-tracker.md), [068 Family space](./068-family-space.md)

## What the person gets
Split with family or friends, running balances, settle-up nudges.

## Acceptance criteria
- [x] Equal and custom splits; balances per person; a drafted reminder message
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/081_shared-expenses-and-settle-up/`.

- Built: engine `lib/engines/records/shared_expenses.dart` (`Splits.equal` hands odd paise to the first people, `Splits.custom` must add up exactly, `Splits.balances` in paise summing to zero, `Splits.settle` greedy fewest payments, `Splits.reminder` drafts the nudge; `SharedExpenses` keeps groups and bills in `expenses/shared_expenses.json` with an undo stack). Screens `lib/records/shared_expenses/` ("Shared expenses" on the Records tab): groups (family member names offered from 068), balances, settle-up cards with Send reminder (share sheet, the person picks the app) and Mark paid. Share / Save the group summary; Undo the last change. Names are free text; the ledger (080) is not changed by shared bills.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
