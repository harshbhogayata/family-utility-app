# 044 — ID card to A4

**Section:** 4. Image basics
**Phase:** 1
**Priority score:** 50 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [021 Images to PDF](./021-images-to-pdf.md), [047 Document scanner](./047-document-scanner.md)

## What the person gets
Front and back of a card on one printable page.

## Acceptance criteria
- [ ] Two captures or two images auto-aligned at actual size on A4 or Letter
- [ ] Output as PDF and JPG
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/044_id-card-to-a4/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
