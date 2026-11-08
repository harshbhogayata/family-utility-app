# 043 — Passport photo maker

**Section:** 4. Image basics
**Phase:** 1
**Priority score:** 50 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [035 Image to exact KB](./035-image-to-exact-kb.md), [041 Crop with ratios](./041-crop-with-ratios.md)

## What the person gets
Country presets, face auto-centre, plain background, print sheet.

## Acceptance criteria
- [ ] Presets: India 35x45 mm, US 2x2 in, UK 35x45, Schengen; custom mm
- [ ] On-device face detection centres and scales the head to spec
- [ ] Export single image at exact KB and a 4x6 or A4 sheet of 6 or 8
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/043_passport-photo-maker/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
