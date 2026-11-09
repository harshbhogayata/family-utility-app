# 009 — Fill forms

**Section:** 1. PDF basics
**Phase:** 1
**Priority score:** 60 / 125 (often × matters × reach)
**Status:** done 10b79fd
**Depends on:** [001 PDF viewer](./001-pdf-viewer.md), [096 Saved addresses and autofill profile](./096-saved-addresses-and-autofill-profile.md)

## What the person gets
Detect and fill form fields; create simple fillable fields.

## Acceptance criteria
- [x] AcroForm fields are detected and editable; flattened on export if chosen
- [x] Non-form PDFs can be filled by placing text boxes anywhere
- [x] Autofill profile values are offered in fields (name, address, DOB)
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/009_fill-forms/`.

- Built: engine `lib/engines/pdf/pdf_form_filler.dart` (pure Dart on the 032 PDF model): `detect` walks /AcroForm /Fields (full dotted names, inherited /FT and /Ff, widgets by page) into text, check box, radio, choice, signature and button fields; `fill` writes /V, builds a Helvetica appearance stream per text/choice widget (honours /DA size, /Q alignment, /MaxLen, multiline wrap), sets /AS on check boxes and radio kids, and sets /NeedAppearances. `flatten` draws each widget's normal appearance into the page as a Form XObject, drops the widgets and the /AcroForm. `PlacedText` boxes go anywhere on any page (non-form PDFs). Tool `lib/tools/fill_forms/` (tap the page to place text; 096 profile values offered as chips under matching fields and in the text-box dialog); output `<name>-filled.pdf` in Files › filled. Batch policy: single. Limits: locked PDFs must be unlocked first (012); text is WinAnsi Helvetica, other scripts show as "?" in the appearance though /V keeps the full Unicode value; XFA-only forms are not read.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
