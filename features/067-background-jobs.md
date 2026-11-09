# 067 — Background jobs

**Section:** 7. Share and transfer
**Phase:** 1
**Priority score:** 48 / 125 (often × matters × reach)
**Status:** done 5302aae
**Depends on:** none

## What the person gets
Long conversions continue when the user leaves, with a notification.

## Acceptance criteria
- [x] Foreground service on Android, background task on iOS; progress and cancel in the notification
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/067_background-jobs/`.

- Engine `BackgroundJobs` (lib/engines/platform) with a `JobHost` interface; `NotificationJobHost` uses `flutter_local_notifications` (progress bar + Cancel action, data-sync foreground service on Android). The generated Android project needs the plugin's `ForegroundService` declared in AndroidManifest with `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_DATA_SYNC` / `POST_NOTIFICATIONS`; without it the host falls back to a plain ongoing notification. iOS shows the progress as notification text while the app uses its background time.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
