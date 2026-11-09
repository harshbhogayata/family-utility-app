# 032 — Compress PDF

**Section:** 3. Compress
**Phase:** 1
**Priority score:** 100 / 125 (often × matters × reach)
**Status:** done d697bdf
**Depends on:** [001 PDF viewer](./001-pdf-viewer.md)

## What the person gets
Low, medium and high presets with size shown before saving.

## Acceptance criteria
- [x] Image downsampling and stream recompression; text stays selectable
- [x] Estimated size shown before the run; actual after
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/032_compress-pdf/`.
- Engine: `lib/engines/pdf/pdf_compressor.dart`, a pure-Dart object rewriter (unpacks object streams, drops unreachable objects, downsamples DCT/Flate photos to JPEG per preset, deflates other streams at level 9, writes a classic xref). Used instead of syncfusion to stay free of licence keys. Encrypted PDFs are refused with a message. UI: `lib/tools/compress_pdf/compress_pdf_screen.dart`.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
