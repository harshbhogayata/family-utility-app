# 077 — Auto check-in

**Section:** 8. Family — shared live data
**Phase:** 2
**Priority score:** 80 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** [076 Live family location](./076-live-family-location.md)

## What the person gets
'Reached safely' in one tap, and automatic on arriving at a saved place.

## Acceptance criteria
- [ ] Manual button posts to the family feed; automatic check-in uses the places from 76
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/077_auto-check-in/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
