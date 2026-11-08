# 022 — PDF to images

**Section:** 2. Convert
**Phase:** 1
**Priority score:** 48 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [001 PDF viewer](./001-pdf-viewer.md)

## What the person gets
One image per page, or all pages into one long image.

## Acceptance criteria
- [ ] JPG or PNG, DPI choice, page range; long-image mode for sharing in chat
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/022_pdf-to-images/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
