# 115 — Recents and favourites

**Section:** 10. Platform
**Phase:** 1
**Priority score:** 100 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [069 Profile per member](./069-profile-per-member.md)

## What the person gets
Used tools float to the top; pin favourites.

## Acceptance criteria
- [ ] Recents per profile; pin and unpin; order persists
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/115_recents-and-favourites/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
