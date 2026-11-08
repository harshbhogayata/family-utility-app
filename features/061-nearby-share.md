# 061 — Nearby share

**Section:** 7. Share and transfer
**Phase:** 1
**Priority score:** 60 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [068 Family space](./068-family-space.md)

## What the person gets
Phone to phone over Wi-Fi Direct with no internet.

## Acceptance criteria
- [ ] Discover family devices by name; transfer 1 GB at LAN speed; resume on drop
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/061_nearby-share/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
