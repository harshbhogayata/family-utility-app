# 108 — Versions

**Section:** 10. Platform
**Phase:** 1
**Priority score:** 48 / 125 (often × matters × reach)
**Status:** done d46302d
**Depends on:** [118 Action history and trash](./118-action-history-and-trash.md)

## What the person gets
Each run keeps the original; roll back any time.

## Acceptance criteria
- [x] Originals kept until trash is emptied; a version list per file
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/108_versions/`.
- `lib/engines/platform/versions.dart`: `Versions.attach(ActionHistory)` keeps a copy of every input of each recorded run in the app's versions folder, listed under each output; roll back first keeps the current bytes as "Before roll back" so it can be undone; `ActionHistory.emptyTrash` purges all kept copies (new `onRecorded` / `onTrashEmptied` hooks on ActionHistory). Versions tool in `lib/tools/versions/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
