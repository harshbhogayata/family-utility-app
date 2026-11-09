# 040 — Resize

**Section:** 4. Image basics
**Phase:** 1
**Priority score:** 80 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** [117 File manager](./117-file-manager.md)

## What the person gets
Pixels, percent, or presets, with aspect lock.

## Acceptance criteria
- [ ] Presets for common form sizes; batch resize
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/040_resize/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
