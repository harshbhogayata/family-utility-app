# 113 — Job notifications

**Section:** 10. Platform
**Phase:** 1
**Priority score:** 48 / 125 (often × matters × reach)
**Status:** done 28fc557
**Depends on:** [067 Background jobs](./067-background-jobs.md)

## What the person gets
Progress, done, tap to share.

## Acceptance criteria
- [x] Every background job posts progress and a result action
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/113_job-notifications/`.

- Engine `JobNotifications` (lib/engines/platform/job_notifications.dart) builds each job's notice: progress + Cancel while running; on the end Done / Failed / Cancelled with Share (tap also shares) and Open. Jobs register files with `JobContext.addOutput` (batch convert, batch everywhere, HEIC, downloads) or `outputOf` (video); a test checks every job body in lib/ does. The payload carries the job id and file paths as JSON so Share still works after the app was closed. `NotificationJobHost.attach()` runs from main() to pick up a tap that launched the app; the permission prompt waits for the first job. Manifest declares the plugin's ForegroundService and ActionBroadcastReceiver; iOS uses notification categories for the buttons.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
