# 017 — Print to PDF

**Section:** 1. PDF basics
**Phase:** 1
**Priority score:** 64 / 125 (often × matters × reach)
**Status:** not started
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

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
