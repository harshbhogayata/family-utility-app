# 128 — Send at original quality

**Section:** 11. Links and WhatsApp essentials
**Phase:** 1
**Priority score:** 80 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [060 Share to any app](./060-share-to-any-app.md)

## What the person gets
Share a photo or video to WhatsApp as a document in one tap, with no compression.

## Acceptance criteria
- [ ] Share-sheet action 'Send original'; wraps the file so WhatsApp treats it as a document
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/128_send-at-original-quality/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
