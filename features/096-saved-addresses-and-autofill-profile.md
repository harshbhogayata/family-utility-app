# 096 — Saved addresses and autofill profile

**Section:** 9. Personal records
**Phase:** 3
**Priority score:** 100 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [057 Secure notes](./057-secure-notes.md)

## What the person gets
Name, addresses, dates kept locally and pasted into any form.

## Acceptance criteria
- [ ] Profile fields copy in one tap; used by PDF form filling; never leaves the device
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/096_saved-addresses-and-autofill-profile/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
