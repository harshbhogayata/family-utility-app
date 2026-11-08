# 089 — BP and sugar logs

**Section:** 9. Personal records
**Phase:** 3
**Priority score:** 80 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** none

## What the person gets
Readings with chart and a PDF for the doctor.

## Acceptance criteria
- [ ] Entry in under 10 s; trend chart; PDF export of any date range
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/089_bp-and-sugar-logs/`.

- Dependency fix (build run 2026-11-08): dropped the link to 094, which depended back on this feature and made both unbuildable; 094 still depends on this one, so the order is unchanged.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
