# 068 — Family space

**Section:** 8. Family — shared live data
**Phase:** 2
**Priority score:** 125 / 125 (often × matters × reach)
**Status:** done b41233b
**Depends on:** [059 On-device mode](./059-on-device-mode.md)

## What the person gets
One shared store; anything a member adds or edits shows on every other phone within seconds.

## Acceptance criteria
- [x] Local-first CRDT store (per-record last-writer-wins with vector clocks) so offline edits merge without conflicts
- [x] Change propagates over LAN in under 3 s and over own-cloud within a minute
- [x] Join a family by scanning a QR from an existing member
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/068_family-space/`.

- Dependency fix (build run 2026-11-08): dropped the link to 079, which depended back on this feature and made both unbuildable; 079 still depends on this one, so the order is unchanged.

- Build run 2026-11-09: engine in `lib/engines/family/` (vector clocks, LWW-per-record store with tombstones, invite + AES-256-GCM family cipher, own-cloud folder transport, `FamilySpace`); Wi-Fi transport in `lib/family/sync/` (the folder the offline policy allows to open sockets). Stack swap: instead of `multicast_dns` + WebSockets, LAN uses `dart:io` TCP with one sealed frame per line and a sealed UDP broadcast beacon for discovery, so no new package and every frame is authenticated by the family key. Own-cloud uses a folder path from the system picker (Drive/iCloud/Syncthing-synced); 079 adds more providers. Family is a LAN feature (68 added to `OfflinePolicy.lanFeatures`). Android: CHANGE_WIFI_MULTICAST_STATE; iOS: NSLocalNetworkUsageDescription.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
