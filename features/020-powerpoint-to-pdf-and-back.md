# 020 — PowerPoint to PDF and back

**Section:** 2. Convert
**Phase:** 1
**Priority score:** 16 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** [030 Convert anything](./030-convert-anything.md)

## What the person gets
PPT/PPTX to PDF, one slide per page, and back.

## Acceptance criteria
- [ ] Slides keep layout; notes optional
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/020_powerpoint-to-pdf-and-back/`.
- Engine `lib/engines/convert/slides.dart`: `PptxReader` reads slides in deck order (sldIdLst → rels), the slide size, every text box and picture with its position and size (EMU → pt), fills, run size/bold/colour and alignment; placeholders positioned only by the layout get a title-band or body-area box. `SlidesPdfWriter` draws one PDF page per slide at the deck's own size (Helvetica, WinAnsi; pictures through the 021 image path), text wrapped inside its box. Speaker notes are optional: a notes page follows each slide that has notes (`pptx-to-pdf-notes`). PDF → PPTX: `PdfToSlides` puts each line of a page in a text box where it sat, scaled onto a 16:9 slide; `PptxWriter` writes a minimal deck (master, blank layout, theme). Old binary .ppt is recognised and refused with a plain "save as .pptx" message, as 018 does for .doc. Registered with Convert anything; tool `lib/tools/powerpoint_pdf/`. Limits: shapes inherit no theme fonts or layout text styles; grouped shapes are read flat; charts and SmartArt are not drawn.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
