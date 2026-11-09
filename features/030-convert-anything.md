# 030 — Convert anything

**Section:** 2. Convert
**Phase:** 1
**Priority score:** 80 / 125 (often × matters × reach)
**Status:** done 068831f
**Depends on:** [117 File manager](./117-file-manager.md)

## What the person gets
Pick a file; the app lists every format it can become.

## Acceptance criteria
- [x] Format list is derived from the file's real type, not its extension
- [x] One conversion engine registry so new converters appear automatically
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/030_convert-anything/`.
- `lib/engines/convert/file_kind.dart` sniffs the real type from magic bytes (images incl. HEIC brands, PDF, ZIP/RAR/7Z/GZip, MP4, MP3) and, for text, from the content (JSON parses, CSV has a consistent column count).
- `lib/engines/convert/convert_registry.dart` is the single registry: `ConvertRegistry.instance.register(...)` adds a converter and it shows up in the tool for every type it accepts. Built in: image to JPG/PNG/BMP/GIF/TIFF (`image` package), CSV to JSON, JSON to CSV, JSON/CSV to text, anything to ZIP (029 codec). Later convert features (HEIC, PDF, Office) register here.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
