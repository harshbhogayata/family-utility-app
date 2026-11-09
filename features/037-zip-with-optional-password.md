# 037 — Zip with optional password

**Section:** 3. Compress
**Phase:** 1
**Priority score:** 48 / 125 (often × matters × reach)
**Status:** done e559ab8
**Depends on:** [029 Archives](./029-archives.md)

## What the person gets
Bundle several files into one archive.

## Acceptance criteria
- [x] Multi-select from files or results; AES password optional
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/037_zip-with-optional-password/`.
- Engine `lib/engines/archive/zip_bundle.dart` reuses 029's pure-Dart `ZipWriter` (WinZip AES-256 when a password is set). Files come from the picker or from the app's own results (`DirectoryResultLibrary`, everything under the documents folder except signatures and private folders). Duplicate names get "(2)"; the password must be typed twice. Output goes to Files › zips.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
