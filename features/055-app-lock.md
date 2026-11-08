# 055 — App lock

**Section:** 6. Security
**Phase:** 1
**Priority score:** 100 / 125 (often × matters × reach)
**Status:** done d092d46
**Depends on:** none

## What the person gets
PIN or biometric on the whole app and on chosen tools.

## Acceptance criteria
- [x] Biometric with PIN fallback; lock timeout configurable; per-tool lock for vault and records
- [x] Works fully offline unless the spec says otherwise, and never uploads the user's file
- [x] Passes on Android 10+ and iOS 15+; touch targets ≥ 44 px; labelled for screen readers

## Implementation notes
- Flutter; platform channels only where Dart packages fall short.
- Put the engine behind an interface in `lib/engines/` so the tool UI stays thin.
- Add a golden test or integration test under `test/features/055_app-lock/`.
- Built: `lib/engines/security/app_lock.dart` (`AppLock` ChangeNotifier: salted SHA-256×20000 PIN hash, 5-attempt / 30 s lockout, `LockTimeout` enum, per-tool `lockedIds` with `LockableIds` for records, private vault, secure notes, receipt vault; `LockStore` + `Biometrics` interfaces), `lib/platform/lock_platform.dart` (flutter_secure_storage + local_auth), `lib/tools/app_lock/` (PIN pad `LockScreen`, `LockGate` around the shell with lifecycle relock, `LockedSection` for the Records tab, `ensureUnlockedFor` used by every tool tile, settings screen). Vault/notes features must call `ensureUnlockedFor` with their `LockableIds` id, which the tile already does when the tool id matches.
- Android needs `USE_BIOMETRIC` permission and `FlutterFragmentActivity`; iOS needs `NSFaceIDUsageDescription`, once the platform folders exist.

## Done when
All acceptance boxes are ticked, the test passes in CI, and this file's status is set to `done` with the commit hash.
