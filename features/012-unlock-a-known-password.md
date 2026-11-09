# 012 — Unlock a known password

**Section:** 1. PDF basics
**Phase:** 1
**Priority score:** 24 / 125 (often × matters × reach)
**Status:** done 2a524de
**Depends on:** [001 PDF viewer](./001-pdf-viewer.md)

## What the person gets
Remove a password the user knows (Aadhaar, bank statements).

## Acceptance criteria
- [x] Enter the password once; a password-free copy is saved
- [x] Hint text explains common formats (Aadhaar: first 4 letters of name + birth year)
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Scouting note (run of 2026-11-09): `PdfProtector.unlock` only handles R6/AES-256. Real Aadhaar/bank PDFs also use R2–R4 (RC4-40/128, AESV2), so add Algorithms 2/6/7 (MD5 + RC4) and per-object keys. `PdfDocumentModel.parse` inflates object streams during parsing and throws on encrypted ones, so it needs an optional hook that decrypts ObjStm data (keyed by the ObjStm's object number) before unpacking.
- Done: `lib/engines/pdf/pdf_unlocker.dart` handles R2–R6 (RC4 40/128, AESV2, AESV3, R5) with user or owner password; `PdfDocumentModel.parse` takes an optional `decrypt` factory that decrypts direct objects and object streams before unpacking. Tests use qpdf-made fixtures as an independent reference.
- Add a golden test or integration test under `test/features/012_unlock-a-known-password/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
