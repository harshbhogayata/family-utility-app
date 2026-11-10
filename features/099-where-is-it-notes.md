# 099 — Where-is-it notes

**Section:** 9. Personal records
**Phase:** 3
**Priority score:** 60 / 125 (often × matters × reach)
**Status:** done 9b96683
**Depends on:** [114 One search](./114-one-search.md)

## What the person gets
Where the spare key, warranty card or wedding album is kept.

## Acceptance criteria
- [x] Searchable notes with optional photo; shared with the family if chosen
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/099_where-is-it-notes/`.
- Notes are private (this phone's own store) unless shared; shared notes go on the family store. A photo stays in this phone's app folder (other phones see that a photo exists). Notes are a One search (114) source; a hit opens this screen filtered to it.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
