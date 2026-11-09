# 001 — PDF viewer

**Section:** 1. PDF basics
**Phase:** 1
**Priority score:** 125 / 125 (often × matters × reach)
**Status:** done 1555094
**Depends on:** [117 File manager](./117-file-manager.md)

## What the person gets
Open any PDF fast, with thumbnails, go-to-page, night mode and continuous or single-page scroll.

## Acceptance criteria
- [x] A 200-page PDF opens to the first page in under 1 s on a mid-range Android phone
- [x] Thumbnail strip, page jump and text selection work; night mode inverts without breaking images
- [x] Last-read page is remembered per file
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/001_pdf-viewer/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
