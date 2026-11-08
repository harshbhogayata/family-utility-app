# 019 — Excel to PDF and back

**Section:** 2. Convert
**Phase:** 1
**Priority score:** 36 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [030 Convert anything](./030-convert-anything.md)

## What the person gets
XLS/XLSX to PDF, and PDF tables to XLSX.

## Acceptance criteria
- [ ] Sheets paginate correctly; PDF tables extract to cells
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/019_excel-to-pdf-and-back/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
