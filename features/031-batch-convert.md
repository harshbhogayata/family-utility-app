# 031 — Batch convert

**Section:** 2. Convert
**Phase:** 1
**Priority score:** 48 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [030 Convert anything](./030-convert-anything.md), [067 Background jobs](./067-background-jobs.md)

## What the person gets
Many files, one target format, one tap.

## Acceptance criteria
- [ ] Progress per file; failures reported without stopping the batch
- [ ] Runs as a background job
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/031_batch-convert/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
