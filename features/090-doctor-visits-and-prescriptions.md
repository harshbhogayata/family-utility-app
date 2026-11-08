# 090 — Doctor visits and prescriptions

**Section:** 9. Personal records
**Phase:** 3
**Priority score:** 75 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [047 Document scanner](./047-document-scanner.md), [071 Shared calendar](./071-shared-calendar.md)

## What the person gets
Notes, scanned prescriptions, next appointment.

## Acceptance criteria
- [ ] Visit record with scanned prescription; next-appointment reminder on the shared calendar
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/090_doctor-visits-and-prescriptions/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
