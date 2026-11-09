# 046 — View and strip EXIF

**Section:** 4. Image basics
**Phase:** 1
**Priority score:** 48 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** [117 File manager](./117-file-manager.md)

## What the person gets
See and remove location, device and date data from photos and videos.

## Acceptance criteria
- [ ] Shows GPS, camera and timestamp; one tap strips all; batch
- [ ] Option to always strip on share
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/046_view-and-strip-exif/`.
- Engine `lib/engines/image/exif_strip.dart`: own small TIFF/EXIF reader (GPS, make/model, software, date, orientation) for JPEG APP1 and PNG eXIf. Strip drops APP1/APP13/COM in JPEG and eXIf/tEXt/iTXt/zTXt/tIME in PNG without re-encoding; a JPEG keeps a one-tag EXIF with its Orientation so it still shows upright. "Always strip on share" is a `ShareEngine.prepare` hook (`StripOnShare`) that swaps photos for clean temp copies; setting kept in shared_preferences. Videos: metadata is not stripped yet (needs a native muxer); the tool accepts JPG and PNG.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
