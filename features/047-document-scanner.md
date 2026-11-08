# 047 — Document scanner

**Section:** 5. Scan and QR
**Phase:** 1
**Priority score:** 125 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [001 PDF viewer](./001-pdf-viewer.md), [021 Images to PDF](./021-images-to-pdf.md)

## What the person gets
Camera capture with edge detection, perspective fix, multi-page and auto-capture.

## Acceptance criteria
- [ ] Live edge detection at 30 fps; auto-capture when steady
- [ ] Multi-page session with reorder and retake; saves as PDF or JPG
- [ ] Share-sheet entry: any app can call the scanner
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/047_document-scanner/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
