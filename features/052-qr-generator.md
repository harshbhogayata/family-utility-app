# 052 — QR generator

**Section:** 5. Scan and QR
**Phase:** 1
**Priority score:** 48 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** none

## What the person gets
Make QR codes for URL, Wi-Fi, UPI, vCard and WhatsApp links.

## Acceptance criteria
- [ ] Logo and colour options; export PNG and SVG; print sheet
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/052_qr-generator/`.
- Engine `lib/engines/qr/qr_generator.dart`: content builders for link, Wi-Fi, UPI, vCard, WhatsApp and text (checked against 051's `QrDecoder`); the matrix comes from the `qr` package (already pulled in by qr_flutter, now listed directly). PNG drawn with `image`, SVG as one path, print sheet = A4 page of 12 codes through 021's `ImagesToPdf`. A logo raises error correction to H; colours with too little contrast are flagged.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
