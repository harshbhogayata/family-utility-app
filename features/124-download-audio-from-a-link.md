# 124 — Download audio from a link

**Section:** 11. Links and WhatsApp essentials
**Phase:** 1
**Priority score:** 60 / 125 (often × matters × reach)
**Status:** done 2be5196
**Depends on:** [123 Download video from a link](./123-download-video-from-a-link.md)

## What the person gets
MP3 or M4A from a video link.

## Acceptance criteria
- [x] Audio-only download; optional trim before save
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/124_download-audio-from-a-link/`.
- Built in `lib/engines/download/audio_link.dart` (link → sound choices, reusing the 123 plugins and the 127 queue) and `lib/engines/download/mp4_audio.dart` (pure-Dart MP4 demuxer: copies the AAC track out of plain or fragmented MP4 into a fresh M4A, no re-encoding, trimmed to whole frames; runs in an isolate). YouTube's own sound-only files are offered first; other sites get "M4A from the video". Direct links to MP3/M4A/… files are saved as they are. MP3 comes only when the site offers MP3 (no MP3 encoder on device, no cloud). Trim works on M4A/MP4 sound; WebM/MP3 files are saved whole. UI: `lib/tools/audio_link/audio_link_screen.dart`, tool id `audio-link`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
