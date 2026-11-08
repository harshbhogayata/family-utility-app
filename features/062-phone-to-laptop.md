# 062 — Phone to laptop

**Section:** 7. Share and transfer
**Phase:** 1
**Priority score:** 80 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** none

## What the person gets
Scan a QR in the laptop browser and move files both ways over local Wi-Fi.

## Acceptance criteria
- [ ] Local HTTP server with a one-time token in the QR; drag-and-drop page in the browser
- [ ] Works with no internet; stops when the app closes
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/062_phone-to-laptop/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
