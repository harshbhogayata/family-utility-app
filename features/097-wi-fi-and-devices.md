# 097 — Wi-Fi and devices

**Section:** 9. Personal records
**Phase:** 3
**Priority score:** 40 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** [057 Secure notes](./057-secure-notes.md), [052 QR generator](./052-qr-generator.md)

## What the person gets
Router passwords, what is connected, serial numbers.

## Acceptance criteria
- [ ] Wi-Fi credentials as QR; device list with serials and purchase dates
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/097_wi-fi-and-devices/`.

- Engine `lib/engines/records/wifi_devices.dart`: networks (name, password, WPA/WEP/open, where) with the `WIFI:` QR text from the QR generator (052); devices with make and model, serial number, purchase date and the network they are on. Stored encrypted with the secure notes key and cipher (057) in `wifi_devices.enc` (`lib/platform/wifi_devices_platform.dart`); nothing is uploaded. Shared and saved text leaves passwords out.
- Screen `lib/records/wifi_devices/wifi_devices_screen.dart` (Wi-Fi and Devices tabs; password hidden until Show QR and password), on the Records tab under Home.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
