# 098 — Maintenance log

**Section:** 9. Personal records
**Phase:** 3
**Priority score:** 48 / 125 (often × matters × reach)
**Status:** done f1cd04c
**Depends on:** [083 Bill reminders](./083-bill-reminders.md)

## What the person gets
AC service, water filter, pest control, with next-due.

## Acceptance criteria
- [x] Recurring intervals per item; reminders; service contact
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/098_maintenance-log/`.

- Engine `lib/engines/records/maintenance_log.dart`: items (AC service, water filter, pest control, chimney, tank, vehicle, other) repeating every 1, 2, 3, 4, 6, 12 or 24 months from the last service; service history with cost and note (late entries slot in by date); service contact name and number with a `tel:` link. On the family store like bills (083), so the household sees one list.
- Reminders through `lib/platform/maintenance_platform.dart` (payload `upkeep:`): 3 days ahead and on the due day at 9:00, the next morning while overdue.
- Screen `lib/records/maintenance/maintenance_screen.dart`, on the Records tab under Home.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
