# 002 — Merge PDF

**Section:** 1. PDF basics
**Phase:** 1
**Priority score:** 64 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [001 PDF viewer](./001-pdf-viewer.md), [117 File manager](./117-file-manager.md)

## What the person gets
Combine several PDFs in a chosen order into one file.

## Acceptance criteria
- [ ] Pick 2+ PDFs, drag to reorder, merge; output opens in the viewer
- [ ] Bookmarks and page sizes of the inputs are preserved
- [ ] Works on 50 MB total input without running out of memory
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/002_merge-pdf/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
