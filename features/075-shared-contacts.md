# 075 — Shared contacts

**Section:** 8. Family — shared live data
**Phase:** 2
**Priority score:** 75 / 125 (often × matters × reach)
**Status:** not started
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

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
