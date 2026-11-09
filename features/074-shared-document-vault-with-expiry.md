# 074 — Shared document vault with expiry

**Section:** 8. Family — shared live data
**Phase:** 2
**Priority score:** 100 / 125 (often × matters × reach)
**Status:** done d47e0c6
**Depends on:** [056 Private vault](./056-private-vault.md), [068 Family space](./068-family-space.md), [045 Blur faces, plates and Aadhaar numbers](./045-blur-faces-plates-and-aadhaar-numbers.md)

## What the person gets
Aadhaar, PAN, passports, vehicle papers and insurance per member, with expiry alerts.

## Acceptance criteria
- [x] Encrypted; per-document expiry date with reminders at 30, 7 and 1 day
- [x] Quick 'send as PDF' and 'send masked' actions
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/074_shared-document-vault-with-expiry/`.

- Shared: each card's member, kind, title and expiry go through the family store; the encrypted file stays on the phone that added it (VaultCipher, key `family_documents_key`). Reminders are checked at app start and hourly by CalendarReminderHost, catching up on any missed while the app was closed.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
