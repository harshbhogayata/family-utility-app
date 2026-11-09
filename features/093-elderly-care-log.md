# 093 — Elderly care log

**Section:** 9. Personal records
**Phase:** 3
**Priority score:** 80 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** [088 Medicine reminders with pill stock](./088-medicine-reminders-with-pill-stock.md), [070 Family roles](./070-family-roles.md)

## What the person gets
Medicines, visits and notes for a parent, shared with siblings.

## Acceptance criteria
- [ ] A care circle with roles; shared medicine schedule and visit notes
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/093_elderly-care-log/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
