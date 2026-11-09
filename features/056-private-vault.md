# 056 — Private vault

**Section:** 6. Security
**Phase:** 1
**Priority score:** 60 / 125 (often × matters × reach)
**Status:** done 3aa5d75
**Depends on:** [055 App lock](./055-app-lock.md), [058 Encrypt any file](./058-encrypt-any-file.md)

## What the person gets
Hide photos and files behind the lock, with a decoy PIN.

## Acceptance criteria
- [x] Files are encrypted at rest with a key in Keystore or Keychain
- [x] Decoy PIN opens an empty vault; vault files are excluded from gallery and backups unless chosen
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/056_private-vault/`.
- Engine `lib/engines/security/private_vault.dart`: AES-256-GCM per file and for the name index, one random key per space in Keystore / Keychain (`lib/platform/vault_platform.dart`). The vault has its own 4–6 digit PIN (salted hash via `PinHasher`); the decoy PIN opens a separate space with its own key that starts empty and never reveals the real one.
- Gallery: files sit in app-private support storage under `vault/` with `.nomedia`. Backups: `res/xml/backup_rules.xml` and `data_extraction_rules.xml` exclude `vault/`; iOS flags it via the `family_utility/backup` channel in `AppDelegate.swift`. Turning backups on moves the folder to `vault_backup/`.
- Originals are copied in, not deleted; the screen tells the person to delete them from the gallery (no photo-library delete package in the stack).

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
