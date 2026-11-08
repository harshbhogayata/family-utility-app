# 033 — PDF to target size

**Section:** 3. Compress
**Phase:** 1
**Priority score:** 100 / 125 (often × matters × reach)
**Status:** not started
**Depends on:** [032 Compress PDF](./032-compress-pdf.md)

## What the person gets
Type a KB or MB limit; the app hits it or says why it cannot.

## Acceptance criteria
- [ ] Iterates quality until under the target; stops with a clear message if impossible
- [ ] Target presets: 100 KB, 200 KB, 500 KB, 1 MB, 2 MB
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/033_pdf-to-target-size/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
