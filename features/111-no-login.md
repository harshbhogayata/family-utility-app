# 111 — No login

**Section:** 10. Platform
**Phase:** 1
**Priority score:** 100 / 125 (often × matters × reach)
**Status:** done 8507290
**Depends on:** none

## What the person gets
Nothing to sign up for; an optional local passcode only.

## Acceptance criteria
- [x] First run to first tool in under 10 s with no account screen
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/111_no-login/`.
- Built: `lib/engines/platform/first_run.dart` (`FirstRun` one-time welcome state behind `FirstRunStore`; `AccountPolicy` = forbidden account copy and packages), `lib/platform/first_run_store.dart` (shared_preferences), `WelcomeCard` on the home grid ("No sign-up, no account", Got it / Set a PIN). CI scans `lib/` and pubspec against `AccountPolicy` every run, so no future feature can add a sign-in screen or an analytics SDK unnoticed. The optional passcode is feature 055.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
