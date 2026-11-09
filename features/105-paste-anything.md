# 105 — Paste anything

**Section:** 10. Platform
**Phase:** 1
**Priority score:** 64 / 125 (often × matters × reach)
**Status:** done 1516ef8
**Depends on:** [106 Smart suggestions](./106-smart-suggestions.md)

## What the person gets
Paste a link, text or file on the home screen and get the matching tools.

## Acceptance criteria
- [x] Clipboard content type detected on paste; matching tools listed in order of likely use
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/105_paste-anything/`.

- Build run 2026-11-09: the home screen's "Paste or pick a file to start" card is now a button. Tapping it reads the clipboard once (Flutter's Clipboard for text, `pasteboard` for pictures) and `PasteAnything.classify` in `lib/engines/platform/paste_anything.dart` sorts it into video link, link, file path (`/…` or `file://`), picture or text. Tools come from a per-kind rule list (files and pictures reuse feature 106's rules), with the member's recent tools moved to the front and network tools hidden in on-device mode. The list shows in a bottom sheet (`lib/tools/paste_anything/paste_sheet.dart`); tapping a tool opens it like the home grid does. This is a home-screen action, not a tool screen, so there is no Share/Save/Undo bar.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
