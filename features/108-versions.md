# 108 — Versions

**Section:** 10. Platform
**Phase:** 1
**Priority score:** 48 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [118 Action history and trash](./118-action-history-and-trash.md)

## What the person gets
Each run keeps the original; roll back any time.

## Acceptance criteria
- [ ] Originals kept until trash is emptied; a version list per file
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/108_versions/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
