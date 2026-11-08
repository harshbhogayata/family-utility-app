# Instructions for every session in this repo

You are building the Family Utility App described in `MASTER_PLAN.md`. The goal is 130 / 130 features done.

## Every session, in this order
1. `git pull origin main`. Read `PROGRESS.md`, then the Build order and Feature tracker in `MASTER_PLAN.md`.
2. Pick the next feature: lowest phase first, then highest score, skipping any whose dependencies (listed in its spec) are not `done`. If a feature is marked `in progress`, finish it first.
3. Open `features/NNN-*.md`. Implement engine first (`lib/engines/`), then the tool UI (`lib/tools/` or the matching folder), then the test under `test/features/NNN_*/`.
4. Run `flutter analyze` and `flutter test`. Nothing is done with a red test.
5. Tick the acceptance boxes in the spec, set its `**Status:**` line to `done <short hash>`, add the feature's row to `PROGRESS.md` (log line plus counts), and commit with `feat(NNN): <name>`.
6. Push to `main` after every finished feature. Keep going until the session's time is up; stop at a clean commit, never mid-feature. If you must stop mid-feature, mark the spec `in progress` with one line on what remains.

## Fixed rules (from MASTER_PLAN.md)
- Offline first; nothing the user gives the app is uploaded.
- No accounts, no analytics, no ads, no cloud AI or paid API keys. On-device ML Kit is fine.
- Flutter 3.x, Dart, Material 3 with the theme in `DESIGN.md`. Use the packages named in the plan's Stack section unless one is broken, in which case note the swap in the spec.
- Every tool screen ends in a result with Share, Save and Undo.

## First session only
If `pubspec.yaml` does not exist: run `flutter create --org app.family --project-name family_utility_app .`, set up the folder layout from `MASTER_PLAN.md`, add the theme from `DESIGN.md`, a four-tab shell (Tools, Family, Records, Files), CI (`.github/workflows/flutter.yml` running analyze and test), and commit as `chore: scaffold`. Then start on features.

## Do not
- Do not reorder or rewrite `MASTER_PLAN.md` sections; only update status cells in the tracker.
- Do not add features that are not in `features/`. If something is missing, add a spec file first and a tracker row.
- Do not leave `PROGRESS.md` out of date.
