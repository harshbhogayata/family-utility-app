# 040 — Resize

**Section:** 4. Image basics
**Phase:** 1
**Priority score:** 80 / 125 (often × matters × reach)
**Status:** done 4369d50
**Depends on:** [117 File manager](./117-file-manager.md)

## What the person gets
Pixels, percent, or presets, with aspect lock.

## Acceptance criteria
- [x] Presets for common form sizes; batch resize
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/040_resize/`.
- Built: `lib/engines/image/image_resizer.dart` (pixels with aspect lock, percent, presets: passport 35×45 mm, 2×2 in, exam photo / signature, profile, Full HD, email; exact presets centre-crop to fill), `lib/tools/resize/resize_screen.dart` (batch via multi-pick, writes beside compressed outputs), registry id `resize`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
