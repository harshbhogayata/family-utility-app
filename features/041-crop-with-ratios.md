# 041 — Crop with ratios

**Section:** 4. Image basics
**Phase:** 1
**Priority score:** 100 / 125 (often × matters × reach)
**Status:** done 63f712a
**Depends on:** [117 File manager](./117-file-manager.md)

## What the person gets
Free, 1:1, 4:3, 3:4, 16:9, 9:16, circle, with visual handles.

## Acceptance criteria
- [x] Handles, rotate by degree, straighten grid; non-destructive until saved
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/041_crop-with-ratios/`.
- Engine `lib/engines/image/crop_engine.dart` (pure Dart `image`): quarter turns, straighten with auto-trim of empty corners, exact-ratio crop, circle → transparent PNG. UI `lib/tools/crop/crop_screen.dart`: 48 px handles with DragStartBehavior.down, 1° nudges + slider, thirds/fine grid, edit-level Undo; nothing is written until Save.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
