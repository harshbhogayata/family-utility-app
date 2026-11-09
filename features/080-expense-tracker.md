# 080 — Expense tracker

**Section:** 9. Personal records
**Phase:** 3
**Priority score:** 100 / 125 (often × matters × reach)
**Status:** done 56d4674
**Depends on:** none

## What the person gets
Categories, receipt photo, monthly view, quick-add from text.

## Acceptance criteria
- [x] Entries with amount, category, note, photo; month and category totals; export CSV
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/080_expense-tracker/`.

- Dependency fix (build run 2026-11-08): dropped the link to 121, which depended back on this feature and made both unbuildable; 121 still depends on this one, so the order is unchanged.
- Engine `lib/engines/records/expense_tracker.dart` (amounts in paise, JSON file in the app folder); receipts copied to `expenses/receipts/`; CSV per month from the result bar.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
