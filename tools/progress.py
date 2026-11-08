#!/usr/bin/env python3
"""Regenerate PROGRESS.md and the tracker status cells in MASTER_PLAN.md from the
spec files. Run after every feature; never edit PROGRESS.md by hand.
"""
import re, pathlib, datetime

ROOT = pathlib.Path(__file__).resolve().parent.parent
rows = []
for p in sorted((ROOT / "features").glob("*.md")):
    t = p.read_text(encoding="utf-8")
    fid = int(p.name[:3])
    status = re.search(r"\*\*Status:\*\*\s*(.+)", t).group(1).strip()
    phase = int(re.search(r"\*\*Phase:\*\*\s*(\d)", t).group(1))
    name = re.search(r"^# \d{3} — (.+)$", t, re.M).group(1).strip()
    rows.append((fid, name, phase, status))

total = len(rows)
done = [r for r in rows if r[3].lower().startswith("done")]
inprog = [r for r in rows if r[3].lower().startswith("in progress")]
by_phase = {p: (sum(1 for r in rows if r[2] == p), sum(1 for r in done if r[2] == p)) for p in (1, 2, 3)}

log = "\n".join(f"- {r[0]:03d} {r[1]} — {r[3]}" for r in sorted(done, key=lambda r: r[0]))
out = f"""# Progress

Done: {len(done)} / {total}  ({100 * len(done) // total}%)
In progress: {', '.join(f'{r[0]:03d}' for r in inprog) or 'none'}
Updated: {datetime.datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')}

| Phase | Features | Done |
| --- | --- | --- |
| 1 — file chores and platform core | {by_phase[1][0]} | {by_phase[1][1]} |
| 2 — family layer | {by_phase[2][0]} | {by_phase[2][1]} |
| 3 — personal records | {by_phase[3][0]} | {by_phase[3][1]} |

## Done
{log or '(none yet)'}
"""
(ROOT / "PROGRESS.md").write_text(out, encoding="utf-8")

# sync tracker status cells in MASTER_PLAN.md
mp = ROOT / "MASTER_PLAN.md"
text = mp.read_text(encoding="utf-8")
status_by_id = {r[0]: r[3] for r in rows}
def fix(m):
    fid = int(m.group(1))
    return f"| {m.group(1)} | {m.group(2)} | {m.group(3)} | {m.group(4)} | {status_by_id.get(fid, m.group(5))} |"
text = re.sub(r"^\| (\d{3}) \| (.+?) \| (.+?) \| (\d+) \| (.+?) \|$", fix, text, flags=re.M)
mp.write_text(text, encoding="utf-8")
print(f"{len(done)}/{total} done, {len(inprog)} in progress")
