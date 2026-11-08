# 111 — No login

**Section:** 10. Platform
**Phase:** 1
**Priority score:** 100 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** none

## What the person gets
Nothing to sign up for; an optional local passcode only.

## Acceptance criteria
- [ ] First run to first tool in under 10 s with no account screen
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/111_no-login/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
