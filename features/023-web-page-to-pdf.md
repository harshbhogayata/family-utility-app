# 023 — Web page to PDF

**Section:** 2. Convert
**Phase:** 1
**Priority score:** 18 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [030 Convert anything](./030-convert-anything.md)

## What the person gets
Paste a URL and get a clean PDF.

## Acceptance criteria
- [ ] Reader-mode and full-page options; works for pages that need no login
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/023_web-page-to-pdf/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
