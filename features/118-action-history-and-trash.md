# 118 — Action history and trash

**Section:** 10. Platform
**Phase:** 1
**Priority score:** 75 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** none

## What the person gets
Every tool run listed with undo and re-run; recently deleted with restore.

## Acceptance criteria
- [ ] History entries link input and output; re-run on a new file; trash retention 30 days
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/118_action-history-and-trash/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
