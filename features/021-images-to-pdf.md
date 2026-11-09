# 021 — Images to PDF

**Section:** 2. Convert
**Phase:** 1
**Priority score:** 125 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** [030 Convert anything](./030-convert-anything.md)

## What the person gets
Any images into one PDF with page size, margins and orientation.

## Acceptance criteria
- [ ] Multi-select from gallery or camera; reorder; A4/Letter/fit-to-image; margins
- [ ] HEIC and WebP accepted without a separate conversion step
- [ ] Output under 2 s for 20 photos
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/021_images-to-pdf/`.
- `lib/engines/pdf/images_to_pdf.dart` writes the PDF directly (no PDF package): JPEGs are embedded as-is with DCTDecode after reading size and EXIF orientation from the bytes; PNG/GIF/WebP/BMP/TIFF are decoded once with `image`, alpha flattened on white, and embedded as JPEG. 20 camera-size JPEGs take well under 2 s because nothing is re-encoded.
- HEIC: `app.family/heic` method channel (`toJpeg`) uses the phone's own decoder; when no handler is present the tool says the phone cannot read HEIC and uploads nothing.
- Camera via `image_picker`; gallery multi-select via `file_picker`; reorder by dragging (ReorderableListView).

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
