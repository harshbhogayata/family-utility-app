# 054 — One-tap searchable scan

**Section:** 5. Scan and QR
**Phase:** 1
**Priority score:** 64 / 125 (often × matters × reach)
**Status:** done 6232042
**Depends on:** [047 Document scanner](./047-document-scanner.md), [008 OCR a scan](./008-ocr-a-scan.md), [032 Compress PDF](./032-compress-pdf.md), [053 Auto-name scans](./053-auto-name-scans.md)

## What the person gets
Capture, OCR, compress and save in one action.

## Acceptance criteria
- [x] A single button runs scan, OCR, compress-to-preset and save with auto-name
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/054_one-tap-searchable-scan/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
