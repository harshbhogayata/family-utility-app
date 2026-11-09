# 005 — Remove pages

**Section:** 1. PDF basics
**Phase:** 1
**Priority score:** 27 / 125 (often × matters × reach)
**Status:** done 5f495f0
**Depends on:** [001 PDF viewer](./001-pdf-viewer.md), [108 Versions](./108-versions.md)

## What the person gets
Delete chosen pages and save.

## Acceptance criteria
- [x] Multi-select and delete with an undo within the session
- [x] Original is kept unless the user chooses overwrite
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/005_remove-pages/`.
- Engine: `lib/engines/pdf/page_remover.dart`, built on the split engine's `PdfSplitSource.buildPages`. UI: `lib/tools/remove_pages/` with PDFium thumbnails (022). Default writes a copy to Files › edited; "Replace the original" first keeps the old file in Versions (108). Undo deletes the copy or writes the original bytes back, then un-marks pages.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
