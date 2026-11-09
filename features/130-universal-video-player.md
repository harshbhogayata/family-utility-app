# 130 — Universal video player

**Section:** 11. Links and WhatsApp essentials
**Phase:** 1
**Priority score:** 100 / 125 (often × matters × reach)
**Status:** in progress
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
- Swap: the plan's `ffmpeg_kit_flutter` is retired, so playback uses `media_kit` (libmpv) for MKV/AVI/MOV/WebM/TS and embedded + SRT subtitles. Engine in `lib/engines/video/video_player_engine.dart` (formats, SRT parser, gesture maths, resume policy, native channel), backend in `media_kit_backend.dart`.
- Brightness changes only this app's window (`app.family/video_player` channel). Volume swipe sets playback volume.
- PiP: Android enters picture-in-picture for the whole activity (`supportsPictureInPicture`). iOS hands MP4/MOV/M4V to an AVPlayer in `AVPictureInPictureController` from the same position (libmpv cannot feed iOS PiP); other containers show a message.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
