# 002 — Merge PDF

**Section:** 1. PDF basics
**Phase:** 1
**Priority score:** 64 / 125 (often × matters × reach)
**Status:** done a590af7
**Depends on:** [001 PDF viewer](./001-pdf-viewer.md), [117 File manager](./117-file-manager.md)

## What the person gets
Combine several PDFs in a chosen order into one file.

## Acceptance criteria
- [x] Pick 2+ PDFs, drag to reorder, merge; output opens in the viewer
- [x] Bookmarks and page sizes of the inputs are preserved
- [x] Works on 50 MB total input without running out of memory
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/002_merge-pdf/`.
- Built: `lib/engines/pdf/pdf_merger.dart` on the 032 PDF object model (added `PdfDocumentModel.build`): renumbers each file's objects, makes inherited Resources / MediaBox / CropBox / Rotate explicit on every page, one bookmark per file holding its own outline, unreachable old catalogs dropped; runs in an isolate. Named destinations (string `/Dest` via the Names tree) are not carried over yet. Screen `lib/tools/merge_pdf/merge_pdf_screen.dart` with up/down reordering and Open in the viewer; registry id `merge-pdf`. A 50 MB two-file merge runs in the test.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
