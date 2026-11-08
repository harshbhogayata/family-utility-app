# 076 — Live family location

**Section:** 8. Family — shared live data
**Phase:** 2
**Priority score:** 80 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [068 Family space](./068-family-space.md), [069 Profile per member](./069-profile-per-member.md)

## What the person gets
Each member shares live location; others see a map with arrive and leave alerts.

## Acceptance criteria
- [ ] Per-member sharing toggle; battery-aware location updates (every 2 min moving, 15 min still)
- [ ] Places (home, school, office) with arrive and leave notifications to the family
- [ ] Location history kept 7 days, local only
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/076_live-family-location/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
