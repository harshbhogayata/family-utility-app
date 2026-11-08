# 116 — Custom home

**Section:** 10. Platform
**Phase:** 2
**Priority score:** 45 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [115 Recents and favourites](./115-recents-and-favourites.md)

## What the person gets
Pin, hide and reorder tools.

## Acceptance criteria
- [ ] Drag to reorder; hide tools; reset to default
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/116_custom-home/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
