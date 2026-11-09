# 011 — Protect with password

**Section:** 1. PDF basics
**Phase:** 1
**Priority score:** 36 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** [001 PDF viewer](./001-pdf-viewer.md)

## What the person gets
Encrypt a PDF with a user password and optional permissions.

## Acceptance criteria
- [ ] AES-256 encryption; opening password and optional print/copy restrictions
- [ ] Password strength indicator; no password stored anywhere
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/011_protect-with-password/`.

- Engine `PdfProtector` (lib/engines/pdf/pdf_protector.dart): pure-Dart standard security handler V5/R6 with the AESV3 crypt filter (pointycastle AES + SHA-2), ISO 32000-2 algorithms 2.B, 8, 9 and 10. Every string and stream is AES-256-CBC with a random IV; /P clears bits 3+12 for no printing and 5 for no copying, bit 10 (accessibility) always stays. The owner password is random and discarded; the user password lives only in the text fields, which are cleared after use. `PasswordStrength.of` drives the meter (length + character kinds, common/repeated passwords are weak). `PdfDocumentModel.write` now keeps /Encrypt in the trailer.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
