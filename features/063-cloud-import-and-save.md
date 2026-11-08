# 063 — Cloud import and save

**Section:** 7. Share and transfer
**Phase:** 1
**Priority score:** 64 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** none

## What the person gets
Google Drive, Dropbox, OneDrive and iCloud as sources and targets.

## Acceptance criteria
- [ ] System document picker on both platforms; remembers a default save folder
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/063_cloud-import-and-save/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
