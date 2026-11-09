# 006 — Reorder pages

**Section:** 1. PDF basics
**Phase:** 1
**Priority score:** 27 / 125 (often × matters × reach)
**Status:** done 3633a4f
**Depends on:** [001 PDF viewer](./001-pdf-viewer.md)

## What the person gets
Drag thumbnails to reorder; add blank pages.

## Acceptance criteria
- [x] Drag-and-drop reorder on the thumbnail grid
- [x] Insert blank page at any position
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/006_reorder-pages/`.
- Engine: `lib/engines/pdf/page_reorder.dart` (`PageLayout`, `PageReorderer`) on the split engine's `buildPages`, which now takes `PdfSplitSource.blank` slots (an empty page sized like the page before it). UI: `lib/tools/reorder_pages/`: long-press drag on the thumbnail grid (LongPressDraggable + DragTarget), a ⋮ menu per page for move earlier/later and blank before/after, and the same as screen-reader custom actions. Saves a copy to Files › edited; Undo removes it, then steps back through changes.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
