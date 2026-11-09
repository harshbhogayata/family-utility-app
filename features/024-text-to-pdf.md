# 024 — Text to PDF

**Section:** 2. Convert
**Phase:** 1
**Priority score:** 27 / 125 (often × matters × reach)
**Status:** done 1c5ba86
**Depends on:** [030 Convert anything](./030-convert-anything.md)

## What the person gets
Paste text, choose a font and size, get a PDF.

## Acceptance criteria
- [x] Supports Indian-language text with proper shaping (Devanagari, Tamil, etc.)
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/024_text-to-pdf/`.
- Shaping: the phone's own text engine (HarfBuzz, with the phone's Noto fonts as fallback) lays out and draws each page; pages are stored as lossless greyscale FlateDecode images at 200 dpi, so the PDF text is not selectable. A `.txt` → PDF converter is also registered with Convert anything (030).

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
