# 072 — Shared shopping list

**Section:** 8. Family — shared live data
**Phase:** 2
**Priority score:** 125 / 125 (often × matters × reach)
**Status:** done d94d2bc
**Depends on:** [068 Family space](./068-family-space.md)

## What the person gets
Ticked live by whoever is at the shop, with who-added and who-ticked.

## Acceptance criteria
- [x] Tick, untick, add with quantity; aisle grouping; a ticked item shows who and when
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/072_shared-shopping-list/`.

- Engine `lib/engines/family/shared_shopping_list.dart` keeps items in the family store's `shopping` collection, so ticks merge across phones like every family record. Aisle is guessed from the name (editable keyword table, walking order); a leading amount ("2 L milk") becomes the quantity. Save writes "Shopping list.txt" to the app's documents folder; Share sends the list as text.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
