# 023 — Web page to PDF

**Section:** 2. Convert
**Phase:** 1
**Priority score:** 18 / 125 (often × matters × reach)
**Status:** done f802eac
**Depends on:** [030 Convert anything](./030-convert-anything.md)

## What the person gets
Paste a URL and get a clean PDF.

## Acceptance criteria
- [x] Reader-mode and full-page options; works for pages that need no login
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/023_web-page-to-pdf/`.
- Engine: `lib/engines/pdf/web_page_to_pdf.dart` parses the HTML on the phone (a small forgiving parser, no scripts run), keeps the article (reader) or all visible text (full page), lays it out with the phone's text engine and writes the PDF with `TextToPdf.writePdf`. The only network code is the GET in `lib/engines/download/web_page_fetcher.dart` (no cookies, no account); feature 23 is added to `OfflinePolicy.networkFeatures`, so on-device mode greys the tool out with its reason.
- Full page is all of the page's visible text, not a screenshot: rendering a full browser snapshot would need a WebView package, which the plan's stack does not list. Images are left out; their alt text is kept in full-page mode.
- Login walls (401/403, or a password form with little text) are reported instead of being saved.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
