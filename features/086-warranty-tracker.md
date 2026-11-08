# 086 — Warranty tracker

**Section:** 9. Personal records
**Phase:** 3
**Priority score:** 75 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [085 Receipt vault](./085-receipt-vault.md), [122 Cross-links](./122-cross-links.md)

## What the person gets
Purchase date, warranty end, bill photo, service contact.

## Acceptance criteria
- [ ] Expiry reminders; linked receipt; service number one tap away
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/086_warranty-tracker/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
