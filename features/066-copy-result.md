# 066 — Copy result

**Section:** 7. Share and transfer
**Phase:** 1
**Priority score:** 48 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** none

## What the person gets
Put an image or text result on the clipboard without saving.

## Acceptance criteria
- [ ] Images copy as image, text as text; clipboard clears after 60 s if the content is sensitive
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/066_copy-result/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
