# 075 — Shared contacts

**Section:** 8. Family — shared live data
**Phase:** 2
**Priority score:** 75 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** [068 Family space](./068-family-space.md), [112 Widgets and quick-settings tile](./112-widgets-and-quick-settings-tile.md)

## What the person gets
Plumber, electrician, doctor, neighbour, and a family speed dial.

## Acceptance criteria
- [ ] Shared list with tags; one-tap call or WhatsApp; speed-dial widget
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/075_shared-contacts/`.
- Engine `lib/engines/family/shared_contacts.dart` keeps contacts in the family store's `contacts` collection (synced like the shopping list), with preset tags (Family, Doctor, Plumber, Electrician, Neighbour, School, Emergency, Other), search, duplicate-number check and Undo. Call opens `tel:`; WhatsApp opens `wa.me` (a 10-digit number without a country code is taken as +91). Screen: `lib/family/contacts/`, reached from the Family tab.
- Speed-dial widget: the star pins up to three contacts; bootstrap feeds the pinned ones to the 112 home widget's speed-dial row whenever they change.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
