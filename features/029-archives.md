# 029 — Archives

**Section:** 2. Convert
**Phase:** 1
**Priority score:** 80 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** [117 File manager](./117-file-manager.md)

## What the person gets
Open, extract and create ZIP, RAR and 7Z.

## Acceptance criteria
- [ ] Browse inside an archive without extracting; extract selected files
- [ ] Create ZIP with optional AES password
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/029_archives/`.
- Engine: `lib/engines/archive/zip_codec.dart` is a small pure-Dart ZIP reader and writer (store and deflate via `dart:io` raw zlib; WinZip AES AE-1/AE-2 read, AES-256 AE-2 write) instead of the `archive` package, so password ZIPs are written with AES rather than the weak ZipCrypto scheme. AES, PBKDF2 and HMAC come from `pointycastle`. Interop is tested against a ZIP locked by Python's pyzipper.
- `lib/engines/archive/archive_engine.dart` detects the format by magic bytes, lists without extracting, extracts only the ticked entries (all decrypted and checked before anything is written; zip-slip paths skipped), and builds ZIPs.
- RAR and 7Z go through the `app.family/archives` method channel (`list`, `extract`). No native handler is wired yet; until one is, the tool tells the person plainly that this phone cannot open RAR/7Z and uploads nothing.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
