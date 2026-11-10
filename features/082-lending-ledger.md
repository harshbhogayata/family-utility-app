# 082 — Lending ledger

**Section:** 9. Personal records
**Phase:** 3
**Priority score:** 48 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** [080 Expense tracker](./080-expense-tracker.md)

## What the person gets
Money lent and borrowed, with reminders.

## Acceptance criteria
- [ ] Who, amount, date, due date, status; reminder notifications
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/082_lending-ledger/`.

- Engine `lib/engines/records/lending_ledger.dart`: lent/borrowed entries (who, amount in paise, date, optional due date, note), repayments capped at what is left, status worked out as Open / Part repaid / Settled, totals and a per-person net. Kept in this phone's own store (`medicineSolo`), never shared with the family or uploaded.
- Reminders through `lib/platform/lending_platform.dart` (flutter_local_notifications, payload `lend:`): the day before and on the due date at 9:00, and the next morning while overdue.
- Screen `lib/records/lending/lending_screen.dart`, listed on the Records tab under Money.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
