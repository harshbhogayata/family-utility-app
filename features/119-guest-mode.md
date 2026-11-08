# 119 — Guest mode

**Section:** 10. Platform
**Phase:** 2
**Priority score:** 24 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [069 Profile per member](./069-profile-per-member.md), [070 Family roles](./070-family-roles.md)

## What the person gets
Hand the phone to a child or relative with only chosen tools visible.

## Acceptance criteria
- [ ] Guest profile with a tool whitelist; exits with the owner's PIN
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/119_guest-mode/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
