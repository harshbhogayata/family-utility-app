# 035 — Image to exact KB

**Section:** 3. Compress
**Phase:** 1
**Priority score:** 100 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** [034 Compress images](./034-compress-images.md), [040 Resize](./040-resize.md)

## What the person gets
Hit an exact size for forms: 20, 50, 100, 200 KB or custom.

## Acceptance criteria
- [ ] Binary search on quality and dimensions until within 5% under target
- [x] Optional dimension lock in px or mm; result shown with a 'fits the limit' tick
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/035_image-to-exact-kb/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.

## Implementation notes (run of 2026-11-09)
- Built and green in CI at 1fb22f0: `lib/engines/image/exact_kb.dart` (binary search on JPG quality, then scale; px or mm lock at 300 dpi; refuses plainly when a locked size cannot fit), `lib/tools/exact_kb/exact_kb_screen.dart` (20/50/100/200 KB chips + custom, 'Fits the limit' tick, Share/Save/Undo), registry id `exact-kb`, test in `test/features/035_image-to-exact-kb/`.
- Remains: guarantee "within 5% under target" — after the quality search, nudge scale up (or quality via finer steps) until size >= 95% of the limit, and assert it in the test (currently asserts > 80%).
