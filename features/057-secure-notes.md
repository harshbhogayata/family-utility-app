# 057 — Secure notes

**Section:** 6. Security
**Phase:** 1
**Priority score:** 100 / 125 (often × matters × reach)
**Status:** done e9c143f
**Depends on:** [055 App lock](./055-app-lock.md)

## What the person gets
Locked notes for IDs, Wi-Fi keys and card last-four.

## Acceptance criteria
- [x] Encrypted at rest; copy a field without opening the note; auto-clear clipboard
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/057_secure-notes/`.
- Built: `lib/engines/security/secure_notes.dart` (`SecureNote`/`NoteField`, `NoteCipher` AES-256-GCM via `cryptography` with a fresh nonce per write, `SecureNotes` ChangeNotifier with clipboard auto-clear; `KeyStore`, `NoteBlobStore`, `ClipboardSink` interfaces), `lib/platform/secure_notes_platform.dart` (key in flutter_secure_storage, blob in the app support dir, system clipboard), `lib/tools/secure_notes/` (list with per-field copy, editor with templates and Share / Save / Undo). Tool id is `LockableIds.secureNotes`, so turning its switch on in App lock asks for the PIN before it opens.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
