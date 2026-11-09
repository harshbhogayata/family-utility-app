# 038 — Shrink-to-send presets

**Section:** 3. Compress
**Phase:** 1
**Priority score:** 80 / 125 (often × matters × reach)
**Status:** in progress
**Depends on:** [032 Compress PDF](./032-compress-pdf.md), [034 Compress images](./034-compress-images.md), [036 Compress video](./036-compress-video.md)

## What the person gets
One-tap buttons such as 'under 25 MB for email' and 'WhatsApp document'.

## Acceptance criteria
- [ ] Each preset picks the right engine for the file type (PDF, image, video)
- [ ] Preset list is editable
- [ ] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [ ] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/038_shrink-to-send-presets/`.

- Remaining (run of 2026-11-09): code and tests are in (75be14f); CI fails only in the screen test 'edit: remove a preset and put it back' because `_addPreset` disposes its dialog controllers on a 1 s Timer that is still pending when the test ends. Dispose them without a timer (e.g. a StatefulWidget dialog that owns the controllers), push, tick the boxes.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
