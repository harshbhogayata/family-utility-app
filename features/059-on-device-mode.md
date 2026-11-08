# 059 — On-device mode

**Section:** 6. Security
**Phase:** 1
**Priority score:** 125 / 125 (often × matters × reach)
**Status:** done 5fbcce5
**Depends on:** none

## What the person gets
A global switch that keeps every tool local, with no network calls.

## Acceptance criteria
- [x] When on, every tool works in airplane mode; tools that need network are greyed with a reason
- [x] Default on; a privacy screen lists what each tool touches
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/059_on-device-mode/`.
- Built: `lib/engines/privacy/on_device_mode.dart` (`OnDeviceMode` ValueNotifier, default on, `DataTouch` enum, store interface), `lib/platform/on_device_mode_store.dart` (shared_preferences), `lib/tools/privacy/privacy_screen.dart` (switch + what-each-tool-touches list), home grid greys network tools with a reason dialog, `ToolEntry` gained `touches` and `networkReason`. New tools must declare both.
- No Share / Save / Undo bar here on purpose: it is a settings switch, not a chore with a result.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
