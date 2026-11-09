# 007 — Rotate pages

**Section:** 1. PDF basics
**Phase:** 1
**Priority score:** 27 / 125 (often × matters × reach)
**Status:** done 7a0efef
**Depends on:** [001 PDF viewer](./001-pdf-viewer.md)

## What the person gets
Rotate single pages or the whole file in 90-degree steps.

## Acceptance criteria
- [x] Per-page and all-pages rotation, saved into the file (not just the view)
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/007_rotate-pages/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
