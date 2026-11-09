# 053 — Auto-name scans

**Section:** 5. Scan and QR
**Phase:** 1
**Priority score:** 48 / 125 (often × matters × reach)
**Status:** done 32adde0
**Depends on:** [047 Document scanner](./047-document-scanner.md), [008 OCR a scan](./008-ocr-a-scan.md)

## What the person gets
File name from detected title and date.

## Acceptance criteria
- [x] OCR picks a title line and a date; editable before save; pattern configurable
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/053_auto-name-scans/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
