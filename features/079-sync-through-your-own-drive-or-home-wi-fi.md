# 079 — Sync through your own Drive or home Wi-Fi

**Section:** 8. Family — shared live data
**Phase:** 2
**Priority score:** 125 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** [068 Family space](./068-family-space.md)

## What the person gets
No third-party server: LAN sync by default, optional sync through a folder in the family's own cloud drive.

## Acceptance criteria
- [ ] LAN: mDNS discovery plus encrypted WebSocket; works with no internet
- [ ] Own-cloud: encrypted change files in a Drive or Dropbox folder the family owns
- [ ] Both can be on at once; the app shows which path each change took
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/079_sync-through-your-own-drive-or-home-wi-fi/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
