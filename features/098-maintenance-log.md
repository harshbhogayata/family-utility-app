# 098 — Maintenance log

**Section:** 9. Personal records
**Phase:** 3
**Priority score:** 48 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [083 Bill reminders](./083-bill-reminders.md)

## What the person gets
AC service, water filter, pest control, with next-due.

## Acceptance criteria
- [ ] Recurring intervals per item; reminders; service contact
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/098_maintenance-log/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
