# 127 — Download queue

**Section:** 11. Links and WhatsApp essentials
**Phase:** 1
**Priority score:** 80 / 125 (often × matters × reach)
**Status:** done 7311ffc
**Depends on:** [067 Background jobs](./067-background-jobs.md)

## What the person gets
Background downloads that resume on reconnect, saved to a chosen folder.

## Acceptance criteria
- [x] Queue with pause, resume, retry; survives app close; per-file progress
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/127_download-queue/`.
- Built on dart:io HttpClient (no new package) in `lib/engines/download/`; Range resume from `<name>.part`; queue saved as JSON; runs as 067 background jobs; on-device mode keeps tasks waiting via NetworkGuard. Waiting tasks retry when the app returns to the foreground (no connectivity package).

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
