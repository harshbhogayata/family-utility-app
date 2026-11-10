# 102 — WhatsApp direct

**Section:** 9. Personal records
**Phase:** 3
**Priority score:** 80 / 125 (often × matters × reach)
**Status:** done 6846b78
**Depends on:** none

## What the person gets
Message a number without saving it.

## Acceptance criteria
- [x] Number with country code opens the chat via wa.me; recent numbers kept locally
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/102_whatsapp-direct/`.

- Built 2026-11-09: engine `lib/engines/records/whatsapp_direct.dart` (number normalising with +91 default, wa.me link, last 10 numbers in the app folder `whatsapp/`); url_launcher opener in `lib/platform/whatsapp_platform.dart`; screen `lib/records/whatsapp_direct/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
