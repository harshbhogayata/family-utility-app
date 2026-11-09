# 114 — One search

**Section:** 10. Platform
**Phase:** 1
**Priority score:** 125 / 125 (often × matters × reach)
**Status:** done 02b6068
**Depends on:** [117 File manager](./117-file-manager.md)

## What the person gets
One box across tools, files, history and records.

## Acceptance criteria
- [x] Indexed search over tool names, file names, OCR text and record fields; results in under 300 ms
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/114_one-search/`.
- Engine: `lib/engines/platform/one_search.dart` (in-memory inverted index, prefix AND match; sources for tools, files + text-file contents, OCR text store, history, records; secret record fields are never indexed). UI: `lib/tools/one_search/one_search_screen.dart`, opened from the search icon on Tools home.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
