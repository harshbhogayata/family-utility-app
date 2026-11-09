# 125 — WhatsApp status saver

**Section:** 11. Links and WhatsApp essentials
**Phase:** 1
**Priority score:** 75 / 125 (often × matters × reach)
**Status:** done d1b57d3
**Depends on:** [117 File manager](./117-file-manager.md)

## What the person gets
Save a contact's photo or video status before it expires.

## Acceptance criteria
- [x] Reads the statuses folder with permission; grid preview; save or share
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/125_whatsapp-status-saver/`.
- Built: `lib/engines/share/status_saver.dart` (filter photos/videos, dedupe WhatsApp + Business, newest first, saved names), `PhoneStatusSource` uses channel `app.family/statuses` (methods `access`, `requestAccess`, `list`, `read`) for the Android 11+ folder grant (ACTION_OPEN_DOCUMENT_TREE at Android/media/com.whatsapp/WhatsApp/Media/.Statuses) and falls back to reading the folders directly on Android 10 and older; iOS shows a plain 'not possible' message. The Kotlin side of the channel lands with the platform folders (there is no `android/` folder in the repo yet). Screen `lib/tools/status_saver/status_saver_screen.dart`, registry id `status-saver`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
