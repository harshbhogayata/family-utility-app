# 057 — Secure notes

**Section:** 6. Security
**Phase:** 1
**Priority score:** 100 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [055 App lock](./055-app-lock.md)

## What the person gets
Locked notes for IDs, Wi-Fi keys and card last-four.

## Acceptance criteria
- [ ] Encrypted at rest; copy a field without opening the note; auto-clear clipboard
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/057_secure-notes/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
