# 095 — Birthdays and anniversaries

**Section:** 9. Personal records
**Phase:** 3
**Priority score:** 80 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [071 Shared calendar](./071-shared-calendar.md)

## What the person gets
Reminders a week ahead, gift ideas attached.

## Acceptance criteria
- [ ] Dates from contacts or entered; reminder at 7 and 1 day; a drafted wish
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/095_birthdays-and-anniversaries/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
