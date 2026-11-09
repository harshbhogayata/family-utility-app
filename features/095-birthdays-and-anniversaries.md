# 095 — Birthdays and anniversaries

**Section:** 9. Personal records
**Phase:** 3
**Priority score:** 80 / 125 (often × matters × reach)
**Status:** done 363b8f4
**Depends on:** [071 Shared calendar](./071-shared-calendar.md)

## What the person gets
Reminders a week ahead, gift ideas attached.

## Acceptance criteria
- [x] Dates from contacts or entered; reminder at 7 and 1 day; a drafted wish
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/095_birthdays-and-anniversaries/`.

- Built 2026-11-09: engine `lib/engines/records/occasions.dart` (family store collection `occasions`, shared like 071's calendar); contacts via flutter_contacts read-only and notifications in `lib/platform/occasion_platform.dart`; READ_CONTACTS and NSContactsUsageDescription added; screen `lib/records/occasions/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
