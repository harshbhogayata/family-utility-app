# 101 — Templates

**Section:** 9. Personal records
**Phase:** 3
**Priority score:** 48 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [096 Saved addresses and autofill profile](./096-saved-addresses-and-autofill-profile.md), [024 Text to PDF](./024-text-to-pdf.md)

## What the person gets
Resume, letters, rent receipt, invoice, NOC, filled and exported as PDF.

## Acceptance criteria
- [ ] 10 templates in English and Hindi; fields prefilled from the autofill profile
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/101_templates/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
