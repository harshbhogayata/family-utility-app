# 046 — View and strip EXIF

**Section:** 4. Image basics
**Phase:** 1
**Priority score:** 48 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [117 File manager](./117-file-manager.md)

## What the person gets
See and remove location, device and date data from photos and videos.

## Acceptance criteria
- [ ] Shows GPS, camera and timestamp; one tap strips all; batch
- [ ] Option to always strip on share
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/046_view-and-strip-exif/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
