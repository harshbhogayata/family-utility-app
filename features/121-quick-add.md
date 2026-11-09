# 121 — Quick-add

**Section:** 10. Platform
**Phase:** 2
**Priority score:** 100 / 125 (often × matters × reach)
**Status:** done e6217a4
**Depends on:** [080 Expense tracker](./080-expense-tracker.md)

## What the person gets
Type 'paid 350 milk' and it lands in the ledger.

## Acceptance criteria
- [x] Parser handles amount, item, person and date in English and Hinglish; confirms before saving
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/121_quick-add/`.
- Parser `lib/engines/records/quick_add.dart`; the ledger is the 080 expense tracker. Screen under Records → Quick add shows amount, item, category, person and date and saves only on "Save to expenses".

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
