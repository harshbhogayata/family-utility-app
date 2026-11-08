# 109 — Accessibility

**Section:** 10. Platform
**Phase:** 2
**Priority score:** 80 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** none

## What the person gets
Dark mode, large text, screen-reader labels, one-hand layout.

## Acceptance criteria
- [ ] All controls labelled; dynamic type up to 200%; contrast 4.5:1; bottom-reachable primary actions
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/109_accessibility/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
