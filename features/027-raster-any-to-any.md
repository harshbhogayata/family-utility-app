# 027 — Raster any to any

**Section:** 2. Convert
**Phase:** 1
**Priority score:** 48 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** [030 Convert anything](./030-convert-anything.md)

## What the person gets
PNG, JPG, GIF, BMP, TIFF in any direction.

## Acceptance criteria
- [ ] Multi-page TIFF handled; quality slider for lossy targets
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/027_raster-any-to-any/`.
- Engine `lib/engines/image/raster_convert.dart`: pure Dart `image` package; every input is normalised to 8-bit RGBA, a multi-page TIFF is split one output per page (`name_pN.ext`). JPG gets the quality slider; JPG, GIF and BMP flatten see-through parts onto white, PNG and TIFF keep them. WebP is accepted as input (WebP output stays in 026).

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
