# 101 — Templates

**Section:** 9. Personal records
**Phase:** 3
**Priority score:** 48 / 125 (often × matters × reach)
**Status:** done 89581fe
**Depends on:** [096 Saved addresses and autofill profile](./096-saved-addresses-and-autofill-profile.md), [024 Text to PDF](./024-text-to-pdf.md)

## What the person gets
Resume, letters, rent receipt, invoice, NOC, filled and exported as PDF.

## Acceptance criteria
- [x] 10 templates in English and Hindi; fields prefilled from the autofill profile
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/101_templates/`.

- Engine `lib/engines/records/templates.dart`: ten templates (resume, rent receipt, invoice, NOC, leave application, authority letter, complaint letter, cover letter, self declaration, address change request), each with English and Hindi labels and text; name, phone, email, address, city, date of birth and today's date come from the saved profile (096); empty fields print as a line to write on.
- PDF through Text to PDF (024) `TextPdfMaker`, so Devanagari is shaped by the phone's fonts; saved in Files › converted like 024.
- Screens `lib/records/templates/templates_screen.dart` (list and editor with live preview, English/Hindi switch, Make PDF; Share, Save, Undo removes the PDF or brings back cleared fields), on the Records tab.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
