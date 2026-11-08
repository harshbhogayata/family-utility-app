# 081 — Shared expenses and settle-up

**Section:** 9. Personal records
**Phase:** 3
**Priority score:** 80 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [080 Expense tracker](./080-expense-tracker.md), [068 Family space](./068-family-space.md)

## What the person gets
Split with family or friends, running balances, settle-up nudges.

## Acceptance criteria
- [ ] Equal and custom splits; balances per person; a drafted reminder message
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/081_shared-expenses-and-settle-up/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
