# 104 — Offline first

**Section:** 10. Platform
**Phase:** 1
**Priority score:** 125 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [059 On-device mode](./059-on-device-mode.md)

## What the person gets
Every tool runs on the device; the few that need network say so.

## Acceptance criteria
- [ ] Airplane-mode test passes for all tools except downloads and cloud; a badge marks network tools
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/104_offline-first/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
