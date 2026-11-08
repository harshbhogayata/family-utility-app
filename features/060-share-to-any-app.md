# 060 — Share to any app

**Section:** 7. Share and transfer
**Phase:** 1
**Priority score:** 125 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** none

## What the person gets
Send any result straight to WhatsApp, Gmail, Drive or Telegram.

## Acceptance criteria
- [ ] Standard share sheet with the result's correct MIME type; remembers last targets
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/060_share-to-any-app/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
