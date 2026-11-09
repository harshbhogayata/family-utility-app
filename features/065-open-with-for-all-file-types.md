# 065 — Open-with for all file types

**Section:** 7. Share and transfer
**Phase:** 1
**Priority score:** 125 / 125 (often × matters × reach)
**Status:** done 0a5a347
**Depends on:** [106 Smart suggestions](./106-smart-suggestions.md)

## What the person gets
The app is registered for 50+ file types so tapping a file lands on the right tool.

## Acceptance criteria
- [x] Android intent filters and iOS document types for PDF, images, video, audio, archives, office files
- [x] Opening a file shows the tools that apply to it
- [x] Android: a one-time "Make this your PDF and image app?" prompt after the first successful open, with a button that deep-links to Settings > Apps > Default apps (or the app's Open-by-default page); never shown again once dismissed
- [x] iOS: document types (UTIs) registered so the app appears in Open in, the share sheet and Files > Open with; the spec accepts that iOS has no default-app setting for file types
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/065_open-with-for-all-file-types/`.

- Build run 2026-11-09: type lists and the inbox/prompt engines in `lib/engines/share/open_with.dart`. Android: one VIEW filter (content/file, 53 MIME types) plus SEND for application/video/audio; MainActivity copies the file into the cache and hands the path over `app.family/open_with` (`initialFiles`, `files`), and `openDefaultsSettings` opens the app's Open-by-default page (Android 12+), falling back to Default apps, then App info. iOS: `CFBundleDocumentTypes` (38 UTIs, rank Alternate), `LSSupportsOpeningDocumentsInPlace` false so the system copies into `Documents/Inbox`, which Dart scans on start and on resume (no native code); imported UTIs for RAR, 7z and Markdown. Opened files land on `OpenedFileScreen` (tools from 106, Share/Save/Undo, the one-time Android card, stored in shared_preferences).

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
