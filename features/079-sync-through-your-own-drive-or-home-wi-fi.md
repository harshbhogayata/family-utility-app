# 079 — Sync through your own Drive or home Wi-Fi

**Section:** 8. Family — shared live data
**Phase:** 2
**Priority score:** 125 / 125 (often × matters × reach)
**Status:** done 83d0f04
**Depends on:** [068 Family space](./068-family-space.md)

## What the person gets
No third-party server: LAN sync by default, optional sync through a folder in the family's own cloud drive.

## Acceptance criteria
- [x] LAN: mDNS discovery plus encrypted WebSocket; works with no internet
- [x] Own-cloud: encrypted change files in a Drive or Dropbox folder the family owns
- [x] Both can be on at once; the app shows which path each change took
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/079_sync-through-your-own-drive-or-home-wi-fi/`.

- Transports come from 068: `lib/family/sync/lan_family_sync.dart` (Wi-Fi) and `FolderFamilySync` in `lib/engines/family/family_sync.dart` (own folder: AES-256-GCM sealed change files). Both run at once when a folder is set.
- Swap: LAN discovery is a sealed UDP broadcast beacon (plus the address in the invite QR) and the link is TCP with every frame sealed AES-256-GCM with the family key, instead of mDNS + WebSocket. Same guarantees (no internet, unreadable without the key) with no extra plugin; mDNS can replace the beacon later if a network blocks broadcasts.
- 079 adds the path record: `FamilyStore` tags every change with `FamilyPath` (This phone / Home Wi-Fi / Own folder), `pathOf()` and `recentChanges`; the Family tab lists the last five with the path each took.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
