# 092 — Vaccination record

**Section:** 9. Personal records
**Phase:** 3
**Priority score:** 50 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** [069 Profile per member](./069-profile-per-member.md)

## What the person gets
Child and adult schedules with due alerts.

## Acceptance criteria
- [ ] Preloaded Indian immunisation schedule; due reminders; certificate scans attached
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/092_vaccination-record/`.
- Child schedule: India's Universal Immunisation Programme (birth to 16 years) from the date of birth; adult: Td every 10 years, yearly flu, Hepatitis B series, pneumococcal at 65. Reminders a week before and on the day (local notifications). Certificates are scans from 047, kept on this phone and linked by path; records ride the family store.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
