# 014 — Page numbers

**Section:** 1. PDF basics
**Phase:** 1
**Priority score:** 8 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** [001 PDF viewer](./001-pdf-viewer.md)

## What the person gets
Stamp page numbers with chosen position, font and start number.

## Acceptance criteria
- [ ] Position presets (6), font size, start number, skip first page option
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/014_page-numbers/`.
- Engine `lib/engines/pdf/page_numbers.dart` (pure Dart, on the 032 PDF object model like 010 Sign): six position presets, size 6–36 pt in the UI (4–72 accepted by the engine), any start number, optional unnumbered first page (numbering then starts on page 2). Numbers are Helvetica, drawn into each page's content between a saved/restored graphics state, so the page's own drawing cannot shift them. Tool `lib/tools/page_numbers/`, one PDF at a time, output `<name>-numbered.pdf` in Files › converted with Share, Save and Undo. Limit: pages with a /Rotate entry get the number on the unrotated page edge.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
