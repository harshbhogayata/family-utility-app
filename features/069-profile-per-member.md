# 069 — Profile per member

**Section:** 8. Family — shared live data
**Phase:** 2
**Priority score:** 125 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** [068 Family space](./068-family-space.md)

## What the person gets
One install, a profile per family member with its own history and favourites.

## Acceptance criteria
- [ ] Switch profile from the home screen; each has its own PIN option, language and recents
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/069_profile-per-member/`.

- Build run 2026-11-09: engine `lib/engines/family/member_profiles.dart` (`MemberProfiles`: add, rename, remove, switch with optional per-profile PIN hashed by `PinHasher`, language, recents capped at 8, favourites), kept in shared_preferences by `lib/platform/profile_store.dart`. UI in `lib/tools/profiles/`: the home avatar is now the profile chip that opens the switcher sheet; long-press a tool tile to star it for the active member; the home screen shows the member's favourites and recents. Language is stored per profile now; the UI strings themselves arrive with 110. History of past runs (ActionHistory) stays shared on the phone; per-member recents and favourites are what the profile owns.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
