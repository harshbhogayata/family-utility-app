# 034 — Compress images

**Section:** 3. Compress
**Phase:** 1
**Priority score:** 125 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** [117 File manager](./117-file-manager.md)

## What the person gets
JPG, PNG and WebP with a quality slider and live size readout.

## Acceptance criteria
- [ ] Slider updates the estimated size live; batch mode for a gallery selection
- [ ] Output never upscales; PNG keeps transparency
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/034_compress-images/`.
- Build run 2026-11-09: uses the pure-Dart `image` package in an isolate. It reads WebP but cannot write it, so WebP comes out as JPG (PNG when transparent); a platform WebP encoder can be swapped in later.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
