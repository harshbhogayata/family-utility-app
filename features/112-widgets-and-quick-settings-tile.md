# 112 — Widgets and quick-settings tile

**Section:** 10. Platform
**Phase:** 2
**Priority score:** 80 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** none

## What the person gets
Home-screen widget and a tile for scan, paste, speed dial and next medicine.

## Acceptance criteria
- [ ] Android widget and quick tile; iOS home and lock-screen widgets
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/112_widgets-and-quick-settings-tile/`.
- Engine `lib/engines/platform/home_widgets.dart`: `WidgetAction` (scan, paste, speed dial, next medicine), `familyapp://widget/<action>` launch links, `WidgetSnapshot` flattened to string keys the native widget reads, and `HomeWidgets` (speed-dial list in shared_preferences, publishes on load / change / resume, routes taps). The next-medicine line takes a `DoseSource`; it says "No medicine due" until 088 Medicine reminders plugs in, and the medicine tap opens the `medicine-reminders` tool once it is registered (this screen until then). Speed-dial numbers are set on the Widgets and tile screen (`lib/tools/home_widget/`) until 075 Shared contacts supplies them.
- Android: `FamilyWidgetProvider` (RemoteViews: next medicine, Scan, Paste, up to three speed-dial buttons that open the dialler) and `ScanTileService` (quick-settings tile opening the scanner; subtitle shows the next medicine on Android 10+). Taps reach Dart over `app.family/home_widget`.
- iOS: `ios/FamilyWidget` WidgetKit extension (small / medium home-screen widgets on iOS 15+, circular / rectangular / inline Lock Screen widgets on iOS 16+) added as a target in `project.pbxproj` and embedded in Runner; data goes through the App Group `group.app.family.familyUtilityApp` (entitlements on both targets). Taps are `familyapp://` deep links handled in Dart (`FlutterDeepLinkingEnabled`). The pbxproj target was written by hand and has not been built in CI (the `flutter` workflow runs analyze and test only); the first Xcode build should confirm it and the App Group signing.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
