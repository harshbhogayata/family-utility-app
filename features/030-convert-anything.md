# 030 — Convert anything

**Section:** 2. Convert
**Phase:** 1
**Priority score:** 80 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [117 File manager](./117-file-manager.md)

## What the person gets
Pick a file; the app lists every format it can become.

## Acceptance criteria
- [ ] Format list is derived from the file's real type, not its extension
- [ ] One conversion engine registry so new converters appear automatically
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/030_convert-anything/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
