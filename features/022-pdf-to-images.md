# 022 — PDF to images

**Section:** 2. Convert
**Phase:** 1
**Priority score:** 48 / 125 (often × matters × reach)
**Status:** done 07812c7
**Depends on:** [001 PDF viewer](./001-pdf-viewer.md)

## What the person gets
One image per page, or all pages into one long image.

## Acceptance criteria
- [x] JPG or PNG, DPI choice, page range; long-image mode for sharing in chat
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/022_pdf-to-images/`.
- Engine `lib/engines/pdf/pdf_to_images.dart`: page ranges ("1-3, 5, 8-"), JPG or PNG, 72 / 150 / 300 dpi, per-page images or one long image (pages scaled to the widest, capped at 16 000 px tall for chat apps). Pages are drawn by PDFium via pdfrx behind `PdfRasterizer` (`lib/platform/pdf_rasterizer_platform.dart`).

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
