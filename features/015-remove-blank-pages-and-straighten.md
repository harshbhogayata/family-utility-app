# 015 — Remove blank pages and straighten

**Section:** 1. PDF basics
**Phase:** 1
**Priority score:** 36 / 125 (often × matters × reach)
**Status:** done fe57ee1
**Depends on:** [001 PDF viewer](./001-pdf-viewer.md), [008 OCR a scan](./008-ocr-a-scan.md)

## What the person gets
Auto-detect blank pages and deskew crooked scans.

## Acceptance criteria
- [x] Blank detection threshold adjustable; preview before removal
- [x] Deskew corrects up to 15 degrees; auto-rotate fixes upside-down pages using OCR orientation
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/015_remove-blank-pages-and-straighten/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
- Engine `lib/engines/pdf/pdf_clean_scan.dart`: ink share inside a 5 % margin for blank pages (slider 0.05–3 %, default 0.4 %), projection-profile deskew within ±15°, upside-down check by reading each inked page upright and flipped with on-device ML Kit; the output keeps the recognised words as an invisible text layer. Tool: `lib/tools/clean_scan/`.
