# 123 — Download video from a link

**Section:** 11. Links and WhatsApp essentials
**Phase:** 1
**Priority score:** 100 / 125 (often × matters × reach)
**Status:** in progress
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
- Built in `lib/engines/download/video_link.dart`: one extractor plugin per site (Instagram, YouTube/Shorts, Facebook, X, Pinterest, Threads) plus a generic Open Graph / direct-file reader as fallback; the registry runs each plugin in its own guard with a timeout, so a crash or hang only fails that plugin. Reads public pages only; YouTube videos whose links are protected are reported, not worked around. Saves through the 127 queue into the chosen folder; personal-use notice stored once in shared_preferences. Android share target: SEND text/plain intent filter + `app.family/shared_link` channel in MainActivity. iOS: paste only for now (no share extension).
- Remaining: flutter CI is green on 1fe53db; the `apk` workflow has not yet passed on any commit (Gradle 504s, then `afterEvaluate` in android/build.gradle.kts from the CI patch), so the MainActivity/manifest change is unverified. Mark done once an apk run is green.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
