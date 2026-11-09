# 107 — Batch everywhere

**Section:** 10. Platform
**Phase:** 1
**Priority score:** 48 / 125 (often × matters × reach)
**Status:** done e56c777
**Depends on:** [067 Background jobs](./067-background-jobs.md)

## What the person gets
Every tool accepts many files.

## Acceptance criteria
- [x] Multi-select in every picker; results grouped; one share for all
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/107_batch-everywhere/`.
- `lib/engines/platform/batch_everywhere.dart`: `BatchPolicy` maps every tool to multi-select picker, a many-file route (Batch screen or Batch convert), a single-file reason (hand placement, one face, one clipboard image) or no picker; `BatchRunner` runs a step over many files as one background job; `BatchReport` groups by output type plus Failed and builds one share. New Batch tool (`lib/tools/batch/`) runs compress PDF, PDF under 1 MB, shrink, resize and strip EXIF over many files. The test audits every `pickFiles` call in lib/tools against the policy.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
