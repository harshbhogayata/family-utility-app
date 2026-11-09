# 031 — Batch convert

**Section:** 2. Convert
**Phase:** 1
**Priority score:** 48 / 125 (often × matters × reach)
**Status:** done 72d3259
**Depends on:** [030 Convert anything](./030-convert-anything.md), [067 Background jobs](./067-background-jobs.md)

## What the person gets
Many files, one target format, one tap.

## Acceptance criteria
- [x] Progress per file; failures reported without stopping the batch
- [x] Runs as a background job
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/031_batch-convert/`.
- Built in `lib/engines/convert/batch_convert.dart`: each file goes through whichever 030 registry converter turns its real (sniffed) type into the chosen format; the whole batch is one 067 background job (cancellable between files), files are read one at a time, and a file that fails is marked with its reason while the rest carry on. UI `lib/tools/batch_convert/batch_convert_screen.dart` (tool id `batch-convert`), outputs land in Files › converted like 030.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
