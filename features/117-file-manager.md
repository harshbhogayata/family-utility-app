# 117 — File manager

**Section:** 10. Platform
**Phase:** 1
**Priority score:** 125 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [114 One search](./114-one-search.md), [118 Action history and trash](./118-action-history-and-trash.md)

## What the person gets
Recents, favourites, folders, and search by name or content.

## Acceptance criteria
- [ ] Browse app files and device storage; sort, move, rename, delete to trash; open-with
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/117_file-manager/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
