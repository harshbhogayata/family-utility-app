# 025 — HEIC to JPG or PNG

**Section:** 2. Convert
**Phase:** 1
**Priority score:** 80 / 125 (often × matters × reach)
**Status:** done 8a74947
**Depends on:** [030 Convert anything](./030-convert-anything.md), [031 Batch convert](./031-batch-convert.md)

## What the person gets
Convert iPhone photos for everyone else, singly or in batch.

## Acceptance criteria
- [x] Share from Photos; JPGs come back in the same order with EXIF orientation applied
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/025_heic-to-jpg-or-png/`.
- Built in `lib/engines/image/heic_convert.dart`: HEIC/HEIF is decoded by the phone's own codec (`flutter_image_compress`, already in the Stack for 026; Android 9+ and iOS decode HEIF natively) behind `HeicCodec` (`lib/platform/heic_platform.dart`, `autoCorrectionAngle` applies EXIF orientation, EXIF not copied, no downscaling). Other pictures in a batch go through the pure-Dart path with `bakeOrientation`. Results keep input order; Share sends them in that order. HEIC→JPG/PNG is also registered in the 030 registry, so Convert anything and Batch convert (031) take iPhone photos. Runs as a 067 background job.
- Share from Photos: Android `SEND`/`SEND_MULTIPLE` `image/*` intent filters; MainActivity copies the shared streams into cache (one folder per picture, original names, shared order) and hands the paths over `app.family/shared_files`; bootstrap opens the HEIC screen, which converts to JPG straight away. iOS: pick from Photos/Files for now (a share extension target is not set up). MainActivity/manifest change is checked by the `apk` workflow only, which is not part of the feature loop.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
