# 067 — Background jobs

**Section:** 7. Share and transfer
**Phase:** 1
**Priority score:** 48 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** none

## What the person gets
Long conversions continue when the user leaves, with a notification.

## Acceptance criteria
- [ ] Foreground service on Android, background task on iOS; progress and cancel in the notification
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/067_background-jobs/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
