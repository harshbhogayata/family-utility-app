# 056 — Private vault

**Section:** 6. Security
**Phase:** 1
**Priority score:** 60 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [055 App lock](./055-app-lock.md), [058 Encrypt any file](./058-encrypt-any-file.md)

## What the person gets
Hide photos and files behind the lock, with a decoy PIN.

## Acceptance criteria
- [ ] Files are encrypted at rest with a key in Keystore or Keychain
- [ ] Decoy PIN opens an empty vault; vault files are excluded from gallery and backups unless chosen
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/056_private-vault/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
