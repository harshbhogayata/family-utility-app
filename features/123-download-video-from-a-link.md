# 123 — Download video from a link

**Section:** 11. Links and WhatsApp essentials
**Phase:** 1
**Priority score:** 100 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [127 Download queue](./127-download-queue.md)

## What the person gets
Instagram reels, posts and stories; YouTube and Shorts; Facebook; X; Pinterest; Threads.

## Acceptance criteria
- [ ] Paste or share a link; quality choice; saved to a chosen folder; personal use notice shown once
- [ ] Extractors isolated as plugins so a broken site does not break the rest
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/123_download-video-from-a-link/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
