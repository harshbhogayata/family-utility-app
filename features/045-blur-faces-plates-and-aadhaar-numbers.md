# 045 — Blur faces, plates and Aadhaar numbers

**Section:** 4. Image basics
**Phase:** 1
**Priority score:** 40 / 125 (often × matters × reach)
**Status:** done 11ef7d0
**Depends on:** [008 OCR a scan](./008-ocr-a-scan.md), [117 File manager](./117-file-manager.md)

## What the person gets
Hide sensitive parts before sharing, baked in.

## Acceptance criteria
- [x] Auto-detect faces and number plates on device; manual blur or black box
- [x] Aadhaar preset masks the first 8 digits found by OCR
- [x] Output has no recoverable original pixels
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/045_blur-faces-plates-and-aadhaar-numbers/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
