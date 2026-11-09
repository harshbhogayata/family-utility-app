# 073 — Shared to-do and notice board

**Section:** 8. Family — shared live data
**Phase:** 2
**Priority score:** 100 / 125 (often × matters × reach)
**Status:** done 4cd4908
**Depends on:** [068 Family space](./068-family-space.md)

## What the person gets
Household tasks with an owner, and pinned notes everyone sees.

## Acceptance criteria
- [x] Tasks with owner, due date and done state; notes pinned to the family screen
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/073_shared-to-do-and-notice-board/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
