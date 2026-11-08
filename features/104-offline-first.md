# 104 — Offline first

**Section:** 10. Platform
**Phase:** 1
**Priority score:** 125 / 125 (often × matters × reach)
**Status:** done 12c34d3
**Depends on:** [059 On-device mode](./059-on-device-mode.md)

## What the person gets
Every tool runs on the device; the few that need network say so.

## Acceptance criteria
- [x] Airplane-mode test passes for all tools except downloads and cloud; a badge marks network tools
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/104_offline-first/`.
- Built: `lib/engines/privacy/offline_policy.dart` — `OfflinePolicy.networkFeatures` {063, 123, 124, 127} is the only set allowed to set `needsNetwork`; LAN tools (061, 062) are not internet tools. `NetworkGuard.run(tool, job)` is the single choke point and throws `OfflineBlocked` while on-device mode is on. The test scans `lib/` for HTTP/socket code outside `lib/engines/download/`, `lib/platform/cloud/`, `lib/family/sync/`, `lib/platform/network/` and checks pubspec for HTTP client packages, so every later feature is held to the airplane-mode rule in CI. The wifi badge on the tile (from the scaffold) plus the tooltip and semantics label mark network tools.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
