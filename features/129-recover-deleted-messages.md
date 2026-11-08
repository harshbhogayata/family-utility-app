# 129 — Recover deleted messages

**Section:** 11. Links and WhatsApp essentials
**Phase:** 1
**Priority score:** 36 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [055 App lock](./055-app-lock.md)

## What the person gets
Notification history keeps messages and media the sender deleted.

## Acceptance criteria
- [ ] Notification listener stores text; media copied from the WhatsApp folder before deletion; opt-in
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/129_recover-deleted-messages/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
