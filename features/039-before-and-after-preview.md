# 039 — Before and after preview

**Section:** 3. Compress
**Phase:** 1
**Priority score:** 48 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** [034 Compress images](./034-compress-images.md)

## What the person gets
Side-by-side or slider comparison with sizes.

## Acceptance criteria
- [ ] Zoomable comparison; size saved and percentage shown
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/039_before-and-after-preview/`.
- Engine `lib/engines/image/before_after.dart` (size saved, percent, divider limits); widget `lib/app/widgets/before_after_view.dart` with a draggable divider or side by side, pinch-zoom through one shared `TransformationController` so both halves zoom together. Opened from each row in Compress images (034) via the Compare button.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
