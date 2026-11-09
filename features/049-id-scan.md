# 049 — ID scan

**Section:** 5. Scan and QR
**Phase:** 1
**Priority score:** 75 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** [047 Document scanner](./047-document-scanner.md), [044 ID card to A4](./044-id-card-to-a4.md)

## What the person gets
Both sides of a card onto one page, auto-aligned.

## Acceptance criteria
- [ ] Guided two-shot flow; output ready to print
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/049_id-scan/`.
- Engine `lib/engines/image/id_scan.dart` (`IdScanFlow`): front → back → review, retake either side without losing the other; the page comes from 044's `IdCardEngine` (edge find, flatten, ID-1 actual size, A4 or Letter, PDF and JPG).
- Screen reuses 047's `ScanCamera` for the live preview with a card-shaped guide; the page is built in a background isolate.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
