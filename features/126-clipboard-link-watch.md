# 126 — Clipboard link watch

**Section:** 11. Links and WhatsApp essentials
**Phase:** 1
**Priority score:** 75 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [123 Download video from a link](./123-download-video-from-a-link.md)

## What the person gets
Copy a link anywhere and the app offers to save it.

## Acceptance criteria
- [ ] Notification or bubble when a supported link is copied; opt-in; never reads other clipboard content
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/126_clipboard-link-watch/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
