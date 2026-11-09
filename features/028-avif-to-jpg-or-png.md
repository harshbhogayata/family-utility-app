# 028 — AVIF to JPG or PNG

**Section:** 2. Convert
**Phase:** 1
**Priority score:** 18 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** [030 Convert anything](./030-convert-anything.md)

## What the person gets
Decode the newest web format.

## Acceptance criteria
- [ ] AVIF decodes offline on Android 12+ and iOS 16+; graceful message elsewhere
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/028_avif-to-jpg-or-png/`.
- Built in `lib/engines/image/avif_convert.dart`: AVIF is sniffed from the `ftyp` box (major brand `avif`/`avis`, or `mif1`/`msf1` listing `avif`) as `FileKind.avif`, and decoded by the phone's own codec (`flutter_image_compress`, already in the Stack; Android 12+ and iOS 16+ decode AVIF natively) behind `AvifCodec` (`lib/platform/avif_platform.dart`). iOS 15 and older are recognised from the OS version and shown the "needs Android 12 or iOS 16" message up front without trying; Android's API level is not visible from Dart without a new channel, so there the decode itself decides and a failure shows the same message. Other pictures picked alongside go through the pure-Dart path. AVIF→JPG/PNG is registered in the 030 registry, so Convert anything and Batch convert (031) take AVIF. Screen `lib/tools/avif/avif_screen.dart` runs as a 067 background job, multi-select, results in Files › converted with Share, Save and Undo.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
