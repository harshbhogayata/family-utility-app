# 010 — Sign PDF

**Section:** 1. PDF basics
**Phase:** 1
**Priority score:** 80 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [001 PDF viewer](./001-pdf-viewer.md)

## What the person gets
Draw, type or import a signature, place it, and reuse saved signatures.

## Acceptance criteria
- [ ] Draw with finger, type in a script font, or import a PNG; saved to the signature library
- [ ] Place, resize and rotate on any page; also initials and date stamps
- [ ] Signed PDF is flattened so the signature cannot be moved by the receiver
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/010_sign-pdf/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
