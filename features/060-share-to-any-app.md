# 060 — Share to any app

**Section:** 7. Share and transfer
**Phase:** 1
**Priority score:** 125 / 125 (often × matters × reach)
**Status:** done 9fcace7
**Depends on:** none

## What the person gets
Send any result straight to WhatsApp, Gmail, Drive or Telegram.

## Acceptance criteria
- [x] Standard share sheet with the result's correct MIME type; remembers last targets
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/060_share-to-any-app/`.
- Built: `lib/engines/share/share_engine.dart` (`MimeTypes` table, `ShareRequest`/`ShareFile`, `ShareSheet` interface, `ShareEngine` with recent targets), `lib/platform/share_sheet.dart` (share_plus `shareXFiles` with per-file MIME, targets read from `ShareResult.raw`, history in shared_preferences). `ResultBar` shows "Last shared to …". Tools share through `ShareEngine.instance.shareFiles(paths)`; never call share_plus directly.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
