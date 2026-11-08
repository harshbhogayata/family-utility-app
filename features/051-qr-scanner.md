# 051 — QR scanner

**Section:** 5. Scan and QR
**Phase:** 1
**Priority score:** 125 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** none

## What the person gets
Scan URL, Wi-Fi, UPI, vCard, event and plain text with a safe preview.

## Acceptance criteria
- [ ] Decodes in under 300 ms; shows the full URL before opening; UPI opens the payment app
- [ ] Wi-Fi codes join the network in one tap; vCards save to contacts
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/051_qr-scanner/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
