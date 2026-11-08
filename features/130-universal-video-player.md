# 130 — Universal video player

**Section:** 11. Links and WhatsApp essentials
**Phase:** 1
**Priority score:** 100 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [065 Open-with for all file types](./065-open-with-for-all-file-types.md)

## What the person gets
Any format, subtitles, gestures, resume, pop-up window.

## Acceptance criteria
- [ ] Plays MKV, AVI, MOV, WebM, TS; SRT and embedded subtitles; brightness and volume gestures; resume position
- [ ] Picture-in-picture on both platforms
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/130_universal-video-player/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
