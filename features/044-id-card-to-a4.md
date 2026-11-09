# 044 — ID card to A4

**Section:** 4. Image basics
**Phase:** 1
**Priority score:** 50 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** [021 Images to PDF](./021-images-to-pdf.md), [047 Document scanner](./047-document-scanner.md)

## What the person gets
Front and back of a card on one printable page.

## Acceptance criteria
- [ ] Two captures or two images auto-aligned at actual size on A4 or Letter
- [ ] Output as PDF and JPG
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/044_id-card-to-a4/`.
- Engine `lib/engines/image/id_card_page.dart`: each side goes through the 047 scanner (edge find + perspective fix), is turned landscape and set to ISO ID-1 (85.6 × 53.98 mm = 1011 × 638 px at 300 dpi), then placed centred, front above back, on an A4 or Letter page at 300 dpi. The JPG is the page; the PDF is the same JPG filling the page box edge to edge via 021's writer, so it prints at actual size.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
