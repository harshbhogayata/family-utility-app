# 017 — Print to PDF

**Section:** 1. PDF basics
**Phase:** 1
**Priority score:** 64 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** [060 Share to any app](./060-share-to-any-app.md), [065 Open-with for all file types](./065-open-with-for-all-file-types.md)

## What the person gets
Appear in every app's share sheet and print dialog as a PDF printer.

## Acceptance criteria
- [ ] Android Print Service and iOS share extension registered
- [ ] Any app's Print or Share produces a PDF saved to the app's files
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/017_print-to-pdf/`.

- Build run 2026-11-09: Android `PdfPrintService` (Kotlin, `BIND_PRINT_SERVICE`) adds the printer "Save as PDF (Family)" to every print dialog; the framework hands it the job as a PDF, which is written to `app_flutter/printed` via a `.part` file and renamed when complete. MainActivity's `app.family/print_to_pdf` channel opens Settings > Printing so the service can be switched on. iOS: no separate share-extension target (a new Xcode target cannot be added safely without Xcode); instead the PDF document type registered by 065 puts the app in the print preview's Share sheet, the file lands in `Documents/Inbox`, and `PrintedPdfs.adoptInbox` copies each new inbox PDF into `printed` once. Engine `lib/engines/pdf/print_to_pdf.dart`; screen `lib/tools/print_to_pdf/` lists printed PDFs with Share, Save (copy to `Saved`) and Undo (last add, keep or remove).

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
