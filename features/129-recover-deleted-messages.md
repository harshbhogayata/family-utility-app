# 129 — Recover deleted messages

**Section:** 11. Links and WhatsApp essentials
**Phase:** 1
**Priority score:** 36 / 125 (often × matters × reach)
**Status:** done 639e04b
**Depends on:** [055 App lock](./055-app-lock.md)

## What the person gets
Notification history keeps messages and media the sender deleted.

## Acceptance criteria
- [x] Notification listener stores text; media copied from the WhatsApp folder before deletion; opt-in
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/129_recover-deleted-messages/`.
- Engine: `lib/engines/share/message_history.dart` (parse, merge with deletion marking, 30-day pruning, export, media rescue). UI: `lib/tools/deleted_messages/`. Android: `MessageHistoryService` (NotificationListenerService) appends WhatsApp notifications to `app_flutter/message_history/inbox.jsonl` only while the `enabled` flag file exists (opt-in); with `rescue_media` it copies media from the WhatsApp folders saved in the last 15 minutes. Channel `app.family/message_history` reports listener access and opens its settings.
- The tool id is lockable from App lock (055). iOS does not allow reading other apps' notifications, so the screen explains that there.
- Media rescue reads the WhatsApp folders directly (READ_EXTERNAL_STORAGE up to API 32; Android/media on newer phones); folders the phone refuses are skipped.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
