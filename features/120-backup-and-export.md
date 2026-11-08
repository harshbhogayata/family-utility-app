# 120 — Backup and export

**Section:** 10. Platform
**Phase:** 2
**Priority score:** 75 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [079 Sync through your own Drive or home Wi-Fi](./079-sync-through-your-own-drive-or-home-wi-fi.md)

## What the person gets
Whole app to a file or the family's own drive, on a schedule; everything exportable as CSV, JSON or PDF.

## Acceptance criteria
- [ ] Encrypted full backup and restore on a new phone; per-section CSV and JSON export
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/120_backup-and-export/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
