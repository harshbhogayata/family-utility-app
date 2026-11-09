# 033 — PDF to target size

**Section:** 3. Compress
**Phase:** 1
**Priority score:** 100 / 125 (often × matters × reach)
**Status:** done dc2c45a
**Depends on:** [032 Compress PDF](./032-compress-pdf.md)

## What the person gets
Type a KB or MB limit; the app hits it or says why it cannot.

## Acceptance criteria
- [x] Iterates quality until under the target; stops with a clear message if impossible
- [x] Target presets: 100 KB, 200 KB, 500 KB, 1 MB, 2 MB
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Engine: `PdfCompressor.toTarget` in `lib/engines/pdf/pdf_compressor.dart` tries the hardest step of `PdfSettings.ladder` first (fails fast with a reason), then binary-searches for the mildest step that fits. UI: `lib/tools/pdf_target_size/pdf_target_size_screen.dart`.
- Add a golden test or integration test under `test/features/033_pdf-to-target-size/`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
