# 096 — Saved addresses and autofill profile

**Section:** 9. Personal records
**Phase:** 3
**Priority score:** 100 / 125 (often × matters × reach)
**Status:** done 592f2a5
**Depends on:** [057 Secure notes](./057-secure-notes.md)

## What the person gets
Name, addresses, dates kept locally and pasted into any form.

## Acceptance criteria
- [x] Profile fields copy in one tap; used by PDF form filling; never leaves the device
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/096_saved-addresses-and-autofill-profile/`.

- Built: engine `lib/engines/records/autofill_profile.dart` (`AutofillProfileBook`: name, DOB, phone, email, any number of `SavedAddress`es and custom fields as one AES-256-GCM blob via 057's `NoteCipher`, key in Keystore/Keychain, file `autofill_profile.enc` in app support; one-tap copy cleared after 60 s; undo stack). `FormFieldMatcher.keyFor` + `suggestionsFor` / `valueFor` give 009 Fill forms the value for a field name (skips father / spouse / nominee fields; custom fields match by label). Screen `lib/records/profile/autofill_profile_screen.dart` ("My details" on the Records tab).

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
