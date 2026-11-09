# 047 — Document scanner

**Section:** 5. Scan and QR
**Phase:** 1
**Priority score:** 125 / 125 (often × matters × reach)
**Status:** in progress
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
- Built: `lib/engines/image/document_scanner.dart` (pure Dart: Otsu + largest bright region edge detector on a ≤160-wide grid, steady-hold auto-capture, 8-point homography perspective fix with bilinear sampling, `ScanSession` with add / retake / reorder / remove / undo, PDF via the 021 engine or JPGs) and `lib/engines/image/scan_entry.dart` (the `app.family/scan` channel).
- Camera: `camera` package image stream (YUV420 Y plane, reduced and turned upright in `lib/tools/document_scanner/scan_camera.dart`); stills are processed in a background isolate with `compute`.
- Share-sheet entry: the platform calls `scan` on `app.family/scan` (Android intent action `app.family.SCAN` in the share sheet, iOS `familyutility://scan`) and receives the saved paths. The manifest / Info.plist entries and CAMERA / NSCameraUsageDescription go in once the platform folders exist (the scaffold has none yet).

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
