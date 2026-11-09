# 036 — Compress video

**Section:** 3. Compress
**Phase:** 1
**Priority score:** 80 / 125 (often × matters × reach)
**Status:** done ad80377
**Depends on:** [067 Background jobs](./067-background-jobs.md)

## What the person gets
Presets for WhatsApp, email and custom bitrate.

## Acceptance criteria
- [x] Hardware encoder when available; progress and cancel
- [x] Presets: WhatsApp 16 MB, email 25 MB, 720p, 480p, custom bitrate
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/036_compress-video/`.

- Encoder is `video_compress` (MediaCodec / AVFoundation hardware encoders). It takes resolution presets, not raw bitrates, so `VideoPlanner` turns a size target or custom bitrate into the largest resolution whose typical bitrate fits, and the compressor steps down a size if the output is still over the limit. Runs through 067 Background jobs for progress, notification and Cancel.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
