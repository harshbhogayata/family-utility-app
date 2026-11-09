# 008 — OCR a scan

**Section:** 1. PDF basics
**Phase:** 1
**Priority score:** 36 / 125 (often × matters × reach)
**Status:** done 2e732c5
**Depends on:** [001 PDF viewer](./001-pdf-viewer.md), [016 Search inside PDFs](./016-search-inside-pdfs.md)

## What the person gets
Make a scanned PDF searchable and selectable using on-device text recognition.

## Acceptance criteria
- [x] Runs offline with ML Kit text recognition; Latin and Devanagari scripts at minimum
- [x] Output PDF keeps the original image with an invisible text layer
- [x] Search inside the OCR'd PDF finds words
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/008_ocr-a-scan/`.
- Added `google_mlkit_text_recognition`; Devanagari model added in `android/app/build.gradle.kts` and `ios/Podfile` (iOS deployment target raised to 15.5 for ML Kit). Text layer uses a Type0 font with a ToUnicode map, render mode 3.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
