# 117 — File manager

**Section:** 10. Platform
**Phase:** 1
**Priority score:** 125 / 125 (often × matters × reach)
**Status:** done 213b1d0
**Depends on:** [118 Action history and trash](./118-action-history-and-trash.md)

## What the person gets
Recents, favourites, folders, and search by name or content.

## Acceptance criteria
- [x] Browse app files and device storage; sort, move, rename, delete to trash; open-with
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/117_file-manager/`.
- Build run 2026-11-09: "Open with" hands the file to the system share sheet (share_plus) rather than adding a new package; default-app handling for every type is feature 065. Phone storage is listed on Android when readable; without file access the folder shows a plain message.

- Dependency fix (build run 2026-11-08): dropped the link to 114, which depended back on this feature and made both unbuildable; 114 still depends on this one, so the order is unchanged.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
