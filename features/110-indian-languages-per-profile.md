# 110 — Indian languages per profile

**Section:** 10. Platform
**Phase:** 2
**Priority score:** 80 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** [069 Profile per member](./069-profile-per-member.md)

## What the person gets
UI in Hindi, Tamil, Telugu, Bengali, Marathi, Gujarati and more.

## Acceptance criteria
- [ ] Strings externalised; 7 languages at launch; per-profile choice
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/110_indian-languages-per-profile/`.
- Strings live in `lib/engines/platform/app_strings.dart` (keyed catalogue, English fallback); `AppStringsScope` / `ProfileStringsScope` in `lib/app/strings_scope.dart` follow the active profile. The shell tabs and the Share / Save / Undo bar use it; `flutter_localizations` (SDK) localises Flutter's own widget strings; iOS lists the seven in `CFBundleLocalizations`. New Language tool sets the active member's choice. Tool names and per-screen copy stay English until moved into the catalogue screen by screen.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
