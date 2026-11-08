# 068 — Family space

**Section:** 8. Family — shared live data
**Phase:** 2
**Priority score:** 125 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [059 On-device mode](./059-on-device-mode.md), [079 Sync through your own Drive or home Wi-Fi](./079-sync-through-your-own-drive-or-home-wi-fi.md)

## What the person gets
One shared store; anything a member adds or edits shows on every other phone within seconds.

## Acceptance criteria
- [ ] Local-first CRDT store (per-record last-writer-wins with vector clocks) so offline edits merge without conflicts
- [ ] Change propagates over LAN in under 3 s and over own-cloud within a minute
- [ ] Join a family by scanning a QR from an existing member
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/068_family-space/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
