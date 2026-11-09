# 120 — Backup and export

**Section:** 10. Platform
**Phase:** 2
**Priority score:** 75 / 125 (often × matters × reach)
**Status:** done 42ee688
**Depends on:** [079 Sync through your own Drive or home Wi-Fi](./079-sync-through-your-own-drive-or-home-wi-fi.md)

## What the person gets
Whole app to a file or the family's own drive, on a schedule; everything exportable as CSV, JSON or PDF.

## Acceptance criteria
- [x] Encrypted full backup and restore on a new phone; per-section CSV and JSON export
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/120_backup-and-export/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
- Engine `lib/engines/platform/backup_export.dart`: AES-256-GCM + PBKDF2 `.fuabak` file (family membership, all family records, settings); restore merges by vector clock so newer edits on the phone win; Undo reverses a restore or removes the last written file.
- Automatic backup daily / weekly / monthly into the family's own sync folder (or a picked one), keeps the last five; the password for it lives in secure storage only.
- Per-section CSV (RFC 4180, formula-safe) and JSON export. PDF export is not in the acceptance criteria and was left out.
