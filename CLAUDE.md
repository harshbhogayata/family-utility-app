# Instructions for every build session in this repo

Goal: 130 / 130 features in `MASTER_PLAN.md` marked done. Sessions run unattended and chain into each other, so follow this loop exactly and never improvise around it.

## The loop
```
0. git pull --rebase origin main
1. If BUILD_CONTROL.md's last line is STOP: end the session now. Do not chain.
2. Lock: if BUILD_LOCK.md exists and its timestamp is under 3 hours old and its session id is not yours: end now, do not chain (another run is active).
   Else write BUILD_LOCK.md with your session id and the current UTC time, commit "chore: lock", push.
3. If pubspec.yaml is missing: scaffold (see below), commit "chore: scaffold", push.
4. NEXT=$(python3 tools/next_feature.py)
   - NONE     -> delete BUILD_LOCK.md, commit, push, report 130/130, end. Do not chain.
   - BLOCKED  -> delete the lock, commit, push, report the problem, end. Do not chain.
5. Open the spec named in NEXT. Set its Status to `in progress`. Implement engine (lib/engines/), then UI (lib/tools/ or the matching folder), then the test (test/features/NNN_*/).
6. flutter analyze && flutter test. Red = not done; fix before moving on.
7. Tick every acceptance box in the spec. Set Status to `done <short hash of the commit you are about to make>` (use the hash after committing; amend once if needed).
8. python3 tools/progress.py ; git add -A ; git commit -m "feat(NNN): <name>" ; git pull --rebase origin main ; git push origin main
9. Touch the timestamp in BUILD_LOCK.md every feature (same commit is fine). Go to 4.
```
When the session is near its limit: finish step 8 for the current feature if minutes remain, otherwise leave the spec `in progress` with one line under "## Implementation notes" saying what remains, run `tools/progress.py`, commit, push. Then delete `BUILD_LOCK.md`, commit "chore: unlock", push, and chain (below).

## Chain
As the last act of a run, if the tally is below 130 / 130, the lock is released, BUILD_CONTROL.md does not say STOP, and this run completed at least one feature or the scaffold: call `fire_trigger` on the scheduled task named "Family utility app build" (find its id with `list_triggers`) with a one-line text naming the next feature. If this run completed nothing, do not chain; the daily schedule retries.

## Fixed rules (from MASTER_PLAN.md)
- Offline first; nothing the user gives the app is uploaded.
- No accounts, analytics, ads, cloud AI or paid API keys. On-device ML Kit is fine.
- Flutter 3.x, Dart, Material 3 with the theme in `DESIGN.md`. Use the packages in the plan's Stack section; if one is broken, note the swap in the spec's Implementation notes.
- Every tool screen ends in a result with Share, Save and Undo.
- Only `tools/progress.py` writes PROGRESS.md and the tracker cells. Never edit them by hand. Never rewrite the plan's sections.
- Do not add features that are not in `features/`. If something is missing, add a spec file with the same header fields first.

## Scaffold (first run only)
`flutter create --org app.family --project-name family_utility_app .` then the folder layout from `MASTER_PLAN.md`, the theme and four-tab shell (Tools, Family, Records, Files) from `DESIGN.md`, and `.github/workflows/flutter.yml` running analyze and test. If Flutter is not installed, install the stable SDK into `/opt/flutter` (or `$HOME/flutter`) and add it to PATH for the session; if that is impossible in this environment, write the reason into `BUILD_CONTROL.md` under a `## Blocked` heading, commit, push, release the lock, end, and do not chain.
