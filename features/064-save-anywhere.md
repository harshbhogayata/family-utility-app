# 064 — Save anywhere

**Section:** 7. Share and transfer
**Phase:** 1
**Priority score:** 100 / 125 (often × matters × reach)
**Status:** done a9a7f75
**Depends on:** [117 File manager](./117-file-manager.md)

## What the person gets
Downloads, Files, a custom folder, or the last-used location.

## Acceptance criteria
- [x] Save dialog remembers the last choice per tool; shows the final path
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/064_save-anywhere/`.
- Engine `lib/engines/share/save_anywhere.dart` (per-tool last choice, free-name final path, safe names); platform `lib/platform/save_platform.dart` (Files = app Documents/Saved, Android shared Download, folder via file_picker getDirectoryPath, choices in shared_preferences); sheet `showSaveAnywhereSheet` in `lib/app/widgets/save_anywhere_sheet.dart`, installed in bootstrap. Tools adopt it from their Save button as they are touched.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
