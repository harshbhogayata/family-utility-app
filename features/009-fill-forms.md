# 009 — Fill forms

**Section:** 1. PDF basics
**Phase:** 1
**Priority score:** 60 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** [001 PDF viewer](./001-pdf-viewer.md), [096 Saved addresses and autofill profile](./096-saved-addresses-and-autofill-profile.md)

## What the person gets
Detect and fill form fields; create simple fillable fields.

## Acceptance criteria
- [ ] AcroForm fields are detected and editable; flattened on export if chosen
- [ ] Non-form PDFs can be filled by placing text boxes anywhere
- [ ] Autofill profile values are offered in fields (name, address, DOB)
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/009_fill-forms/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
