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
- Remains: (1) non-Latin text in the renderer (embed Inter); (2) PDF → DOCX: text fragments with positions (pdfrx on device behind an interface; check the pdfrx 2.x text API before use) → paragraphs by line gaps, headings by font size, tables by aligned columns → `DocxWriter`; (3) legacy .DOC through a platform channel or a plain refusal; (4) the tool screen and registry entry.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
