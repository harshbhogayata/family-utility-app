# 037 — Zip with optional password

**Section:** 3. Compress
**Phase:** 1
**Priority score:** 48 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [029 Archives](./029-archives.md)

## What the person gets
Bundle several files into one archive.

## Acceptance criteria
- [ ] Multi-select from files or results; AES password optional
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/037_zip-with-optional-password/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
