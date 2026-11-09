# 106 — Smart suggestions

**Section:** 10. Platform
**Phase:** 1
**Priority score:** 100 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** [115 Recents and favourites](./115-recents-and-favourites.md)

## What the person gets
Open a PDF, see merge, sign, compress; open a photo, see resize, remove metadata.

## Acceptance criteria
- [ ] Suggestion rules per file type, reordered by the user's history
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/106_smart-suggestions/`.

- Build run 2026-11-09: rules engine `lib/engines/platform/smart_suggestions.dart` (kind from the name or from the detected `FileKind`, a fixed tool list per kind, tools in the active member's recents moved to the front newest first, filtered to registered tools and to on-device mode). `SuggestionsBar` (`lib/tools/smart_suggestions/`) shows "Suggested for this PDF" chips in the Files tab once a file is opened or long-pressed; chips open the tool through `openTool`, which records it as recent. Only file names are read; nothing is uploaded.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
