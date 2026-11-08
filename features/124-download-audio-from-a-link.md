# 124 — Download audio from a link

**Section:** 11. Links and WhatsApp essentials
**Phase:** 1
**Priority score:** 60 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [123 Download video from a link](./123-download-video-from-a-link.md)

## What the person gets
MP3 or M4A from a video link.

## Acceptance criteria
- [ ] Audio-only download; optional trim before save
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/124_download-audio-from-a-link/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
