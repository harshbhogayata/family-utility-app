# 071 — Shared calendar

**Section:** 8. Family — shared live data
**Phase:** 2
**Priority score:** 125 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** [068 Family space](./068-family-space.md)

## What the person gets
Events with a colour per member, reminders, repeat rules.

## Acceptance criteria
- [ ] Create, edit, repeat, remind; conflicts merge; optional one-way export to the phone calendar
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/071_shared-calendar/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
