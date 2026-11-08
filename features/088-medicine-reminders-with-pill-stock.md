# 088 — Medicine reminders with pill stock

**Section:** 9. Personal records
**Phase:** 3
**Priority score:** 125 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [069 Profile per member](./069-profile-per-member.md), [070 Family roles](./070-family-roles.md)

## What the person gets
Dose times per person, taken or skipped log, tablets left, refill reminder.

## Acceptance criteria
- [ ] Reminders fire reliably (exact alarms on Android); snooze and taken; stock decrements per dose
- [ ] Per-member schedule visible to carers with permission
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/088_medicine-reminders-with-pill-stock/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
