# 048 — Scan filters

**Section:** 5. Scan and QR
**Phase:** 1
**Priority score:** 100 / 125 (often × matters × reach)
**Status:** done cb126a8
**Depends on:** [047 Document scanner](./047-document-scanner.md)

## What the person gets
Black-and-white, colour-boost, grayscale, shadow and glare removal.

## Acceptance criteria
- [x] Filters apply per page or whole document; adjustable contrast
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/048_scan-filters/`.
- Built: `lib/engines/image/scan_filters.dart` (pure Dart: grayscale, colour boost, shadow removal by dividing out a block-max paper level, black and white as shadow-free local-mean threshold, glare fill from the surrounding paper colour; contrast 50–200 % on every filter). `ScanPage` keeps the captured `original` so filters never stack; `ScanSession.applyFilter` / `replacePages` apply to one page or all as one undo step.
- UI lives in the 047 review screen: filter chips, contrast slider, This page / All pages, Apply filter; filtering runs in a background isolate.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
