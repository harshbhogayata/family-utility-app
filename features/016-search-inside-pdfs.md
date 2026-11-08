# 016 — Search inside PDFs

**Section:** 1. PDF basics
**Phase:** 1
**Priority score:** 36 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [001 PDF viewer](./001-pdf-viewer.md), [114 One search](./114-one-search.md)

## What the person gets
Find text inside one file or across every saved PDF.

## Acceptance criteria
- [ ] In-file search with hit list and highlights
- [ ] Library-wide search over indexed text, including OCR'd scans, under 1 s for 500 files
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/016_search-inside-pdfs/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
