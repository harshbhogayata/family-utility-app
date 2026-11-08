# 051 — QR scanner

**Section:** 5. Scan and QR
**Phase:** 1
**Priority score:** 125 / 125 (often × matters × reach)
**Status:** done 012db23
**Depends on:** none

## What the person gets
Scan URL, Wi-Fi, UPI, vCard, event and plain text with a safe preview.

## Acceptance criteria
- [x] Decodes in under 300 ms; shows the full URL before opening; UPI opens the payment app
- [x] Wi-Fi codes join the network in one tap; vCards save to contacts
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/051_qr-scanner/`.
- Built: `lib/engines/qr/` (pure-Dart decoder for URL, Wi-Fi, UPI, vCard, vEvent, text + `QrActions` interface), `lib/tools/qr_scanner/` (mobile_scanner camera screen, result screen, platform actions via url_launcher, wifi_iot, flutter_contacts, add_2_calendar, share_plus, path_provider), shared `lib/app/widgets/result_bar.dart` (Share / Save / Undo) for every later tool.
- Android needs CAMERA in the manifest and iOS NSCameraUsageDescription / NSContactsUsageDescription once the platform folders exist (scaffold has none yet).

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
