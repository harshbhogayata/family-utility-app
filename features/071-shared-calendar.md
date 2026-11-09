# 071 — Shared calendar

**Section:** 8. Family — shared live data
**Phase:** 2
**Priority score:** 125 / 125 (often × matters × reach)
**Status:** done 1354986
**Depends on:** [068 Family space](./068-family-space.md)

## What the person gets
Events with a colour per member, reminders, repeat rules.

## Acceptance criteria
- [x] Create, edit, repeat, remind; conflicts merge; optional one-way export to the phone calendar
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/071_shared-calendar/`.

- Engine `lib/engines/family/shared_calendar.dart` stores events in the family store's `calendar` collection (per-record vector-clock merge from 068). Repeats daily/weekly/monthly/yearly with optional end day; monthly/yearly skip months without that day.
- Reminders: `CalendarReminderWatcher` checks once a minute while the app runs (started by `CalendarReminderHost` in the widget tree) and shows a local notification; so a reminder made on another phone fires here too. Share exports .ics; Save sends events one-way to the phone calendar via add_2_calendar.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
