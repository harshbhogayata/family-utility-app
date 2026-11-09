# 058 — Encrypt any file

**Section:** 6. Security
**Phase:** 1
**Priority score:** 24 / 125 (often × matters × reach)
**Status:** done d74c332
**Depends on:** none

## What the person gets
Password-protect any file and decrypt later.

## Acceptance criteria
- [x] AES-256-GCM; output is a single portable file; decrypt on any device with the app
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/058_encrypt-any-file/`.
- Engine: `lib/engines/security/file_crypt.dart`. Format `.fuaenc`: "FUAENC", version, KDF id, PBKDF2-HMAC-SHA256 rounds (210 000), 16-byte salt, 12-byte nonce, then AES-256-GCM over [name length · name · bytes] with the header as associated data. The test decrypts a vector made by Python's `cryptography`, so the format is standard. Whole file is held in memory; very large files would need a chunked v2.
- UI: `lib/tools/encrypt_file/` (tool id `encrypt-file`). Picking a `.fuaenc` file switches the screen to open mode.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
