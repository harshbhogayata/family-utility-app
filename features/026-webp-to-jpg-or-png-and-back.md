# 026 — WebP to JPG or PNG and back

**Section:** 2. Convert
**Phase:** 1
**Priority score:** 48 / 125 (often × matters × reach)
**Status:** done 012d5cd
**Depends on:** [030 Convert anything](./030-convert-anything.md)

## What the person gets
Fix the format websites hand you.

## Acceptance criteria
- [x] Both directions, transparency preserved for PNG
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/026_webp-to-jpg-or-png-and-back/`.
- Engine `lib/engines/image/webp_convert.dart`: decodes WebP/JPG/PNG with the `image` package; PNG keeps alpha, JPG flattens onto white and says so. The `image` package cannot write WebP, so WebP output goes through `flutter_image_compress` (the phone's codec) behind `WebpEncoder`, fed a PNG so transparency survives.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
