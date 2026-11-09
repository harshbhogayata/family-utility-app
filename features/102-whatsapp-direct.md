# 102 — WhatsApp direct

**Section:** 9. Personal records
**Phase:** 3
**Priority score:** 80 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** none

## What the person gets
Message a number without saving it.

## Acceptance criteria
- [ ] Number with country code opens the chat via wa.me; recent numbers kept locally
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/102_whatsapp-direct/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
