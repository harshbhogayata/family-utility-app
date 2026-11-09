# 018 — Word to PDF and back

**Section:** 2. Convert
**Phase:** 1
**Priority score:** 80 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** [030 Convert anything](./030-convert-anything.md)

## What the person gets
DOC/DOCX to PDF, and PDF to editable DOCX.

## Acceptance criteria
- [ ] DOCX to PDF renders fonts, tables and images faithfully offline
- [ ] PDF to DOCX keeps paragraphs, headings and tables editable
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/018_word-to-pdf-and-back/`.
- Built so far: `lib/engines/convert/word_document.dart` — document model (headings, paragraphs with runs: bold / italic / underline / size / colour / font, alignment, tables, images), `DocxReader` (ZIP + `xml` package; localised heading style ids from styles.xml, hyperlinks, tabs, breaks, inline pictures with their size) and `DocxWriter` (editable DOCX with Heading 1–6 and Table Grid styles). Test in `test/features/018_word-to-pdf-and-back/`.
- Tried `pdf: ^3.11.0` for the renderer (commit e6347c4, reverted): it resolved `archive` 4.0.9, whose ZLibDecoder lacks the `decodeLazy` that image 4.11.0's PNG decoder calls, so every test failed to compile. Next try: also pin `archive` to a release that has `decodeLazy` (check archive's changelog), or write the PDF directly as 021 does. The reverted `word_pdf_renderer.dart` and its test can be restored with `git show e6347c4`.
- DOCX → PDF renderer: `lib/engines/convert/word_pdf_renderer.dart` writes the PDF directly (no `pdf` package, which clashed on `archive`): A4 layout, word wrap, page flow, alignment incl. justify, headings, bold / italic / underline / colour / size, base fonts Helvetica / Times / Courier chosen by font name, ruled tables with equal columns, pictures re-encoded to JPEG via `ImagesToPdf.prepare` (unreadable ones become a labelled box). Text outside WinAnsi prints as '?'; embedding Inter (Type0 + Identity-H) for non-Latin text is still to do.
- PDF → DOCX: `lib/engines/convert/pdf_to_word.dart` (`PdfToWord`) rebuilds lines from positioned text pieces, then headings by height against the body (lower median), paragraphs by line gaps (de-hyphenated), tables from runs of lines with the same aligned columns; `lib/platform/pdfrx_text_source.dart` reads fragments with pdfrx on device. Converters in `word_converters.dart` (docx-to-pdf, pdf-to-docx, a plain refusal for .doc), registered with Convert anything in bootstrap; `FileKind.docx` / `FileKind.doc` sniffed from content. Tool screen `lib/tools/word_pdf/word_pdf_screen.dart`, registry id `word-pdf`.
- Non-Latin text: `truetype_font.dart` reads the bundled Inter (cmap 4/12, hmtx); words the base fonts cannot draw are set in it, embedded as Type0 / CIDFontType2 / Identity-H with a ToUnicode map so text stays selectable. pdfrx 2.x: `loadText()` now returns `PdfPageRawText`; the source uses `loadStructuredText()` fragments.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
