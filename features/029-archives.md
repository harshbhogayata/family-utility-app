# 029 — Archives

**Section:** 2. Convert
**Phase:** 1
**Priority score:** 80 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [117 File manager](./117-file-manager.md)

## What the person gets
Open, extract and create ZIP, RAR and 7Z.

## Acceptance criteria
- [ ] Browse inside an archive without extracting; extract selected files
- [ ] Create ZIP with optional AES password
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/029_archives/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
