# 003 — Split PDF

**Section:** 1. PDF basics
**Phase:** 1
**Priority score:** 36 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** [001 PDF viewer](./001-pdf-viewer.md)

## What the person gets
Split by page range, every N pages, or by file size.

## Acceptance criteria
- [ ] Range input accepts forms like 1-3, 5, 8-10
- [ ] Every-N and by-size modes produce correctly numbered parts
- [ ] Parts are saved as a set and offered as a zip
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/003_split-pdf/`.

- Engine `PdfSplitter` / `PdfSplitSource` (lib/engines/pdf/pdf_splitter.dart) reuses the pure-Dart PDF model from 032: parses once, walks the page tree copying inherited MediaBox/CropBox/Rotate/Resources onto each page, and writes each part with only the objects its pages reach. `PageRanges.parse` takes `1-3, 5, 8-10`, open ends (`8-`), dashes, `to` and `;`. Every-N and by-size (greedy, a lone oversize page is its own flagged part) name parts `<name> part NN (pA-B).pdf` with zero padding. Parts are saved in `split/<name> <time>/` with `<name> parts.zip` (ZipWriter from 029); Share sends the ZIP, a second button shares the separate PDFs, Undo deletes the set.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
