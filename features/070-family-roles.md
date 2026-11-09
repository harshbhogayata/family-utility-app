# 070 — Family roles

**Section:** 8. Family — shared live data
**Phase:** 2
**Priority score:** 60 / 125 (often × matters × reach)
**Status:** done 9b5bd93
**Depends on:** [068 Family space](./068-family-space.md), [069 Profile per member](./069-profile-per-member.md)

## What the person gets
Who can see and edit what, per section.

## Acceptance criteria
- [x] Roles: adult, child, guest; per-section read or write; child cannot see money or vault by default
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/070_family-roles/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
- Engine `lib/engines/family/family_roles.dart`: role on each member record, per-role section table in the family store's `roles` collection (so every phone applies the same rules); defaults hide money and vault from children; only adults change rules, and the last adult cannot be demoted. Undo reverses the last change.
- Screen `lib/family/roles/family_roles_screen.dart`, opened from the Platform tools. Sections read `FamilyRoles.instance.iCanSee/iCanEdit`; Phase 3 money and vault screens gate on it as they are built.
