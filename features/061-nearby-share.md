# 061 — Nearby share

**Section:** 7. Share and transfer
**Phase:** 1
**Priority score:** 60 / 125 (often × matters × reach)
**Status:** in progress
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

- Build run 2026-11-09: engine `lib/engines/transfer/nearby_share.dart` (offer, inbox with resumable part files), sockets in `lib/platform/network/nearby_share_net.dart`, UI `lib/tools/nearby_share/`. Swap: Wi-Fi Direct needs per-platform channels (iOS has no Wi-Fi Direct API), so phones meet on the same Wi-Fi or one phone's hotspot, which needs no internet either. Discovery is a beacon sealed with the family key (068), so only family phones appear, by member name. CI checks a 32 MB loopback transfer and a resume; 1 GB is the same stream path.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
