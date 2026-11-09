# 126 — Clipboard link watch

**Section:** 11. Links and WhatsApp essentials
**Phase:** 1
**Priority score:** 75 / 125 (often × matters × reach)
**Status:** done 44ef7df
**Depends on:** [123 Download video from a link](./123-download-video-from-a-link.md)

## What the person gets
Copy a link anywhere and the app offers to save it.

## Acceptance criteria
- [x] Notification or bubble when a supported link is copied; opt-in; never reads other clipboard content
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/126_clipboard-link-watch/`.
- Built in `lib/engines/download/clipboard_watch.dart`: opt-in switch (off by default, kept in shared_preferences); while on, the clipboard is read once each time the app comes to the front (AppLifecycleListener; Android 10+ only lets the foreground app read it) and only a link one of the 123 site plugins handles is offered, as a floating snack-bar bubble with Save that opens the 123 screen. Any other clipboard text is dropped immediately and never stored; the same copy is not offered twice. A background clipboard notification is not possible on Android 10+ or iOS without a keyboard/overlay service, so the bubble is in-app. Screen: `lib/tools/clipboard_watch/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
