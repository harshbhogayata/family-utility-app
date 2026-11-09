# 042 — Rotate and flip

**Section:** 4. Image basics
**Phase:** 1
**Priority score:** 36 / 125 (often × matters × reach)
**Status:** done 47fa235
**Depends on:** [117 File manager](./117-file-manager.md)

## What the person gets
Rotate in 90-degree steps, flip horizontal or vertical, batch.

## Acceptance criteria
- [x] EXIF orientation respected and written
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/042_rotate-and-flip/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
- Engine `lib/engines/image/rotate_flip.dart`: turns and flips compose as the eight EXIF orientations; JPGs are changed losslessly by rewriting (or adding) the EXIF orientation tag on top of the existing one, other pictures are baked upright, transformed and saved as PNG. Tool `lib/tools/rotate_flip/` takes many pictures at once.
