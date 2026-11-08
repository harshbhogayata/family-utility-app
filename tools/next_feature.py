#!/usr/bin/env python3
"""Print the next feature to build, or NONE when all 130 are done.

Rules: lowest phase first, then highest score, then lowest id; a feature is
eligible only when every dependency is done; an `in progress` feature always
comes first. Reads the spec files, so the specs are the single source of truth.
"""
import re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
specs = {}
for p in sorted((ROOT / "features").glob("*.md")):
    t = p.read_text(encoding="utf-8")
    fid = int(p.name[:3])
    status = re.search(r"\*\*Status:\*\*\s*(.+)", t).group(1).strip().lower()
    phase = int(re.search(r"\*\*Phase:\*\*\s*(\d)", t).group(1))
    score = int(re.search(r"\*\*Priority score:\*\*\s*(\d+)", t).group(1))
    deps = [int(x) for x in re.findall(r"\[(\d{3}) ", t.split("**Depends on:**", 1)[1].split("\n", 1)[0])]
    name = re.search(r"^# \d{3} — (.+)$", t, re.M).group(1).strip()
    specs[fid] = dict(id=fid, name=name, file=p.name, status=status, phase=phase, score=score, deps=deps)

done = {i for i, s in specs.items() if s["status"].startswith("done")}
if len(done) == len(specs):
    print("NONE"); sys.exit(0)

in_prog = [s for s in specs.values() if s["status"].startswith("in progress")]
if in_prog:
    s = in_prog[0]
    print(f"{s['id']:03d} {s['name']} | features/{s['file']} | resume (in progress)"); sys.exit(0)

eligible = [s for s in specs.values() if s["id"] not in done and all(d in done for d in s["deps"])]
if not eligible:
    print("BLOCKED: no eligible feature; check dependency cycles"); sys.exit(2)
s = sorted(eligible, key=lambda s: (s["phase"], -s["score"], s["id"]))[0]
print(f"{s['id']:03d} {s['name']} | features/{s['file']} | phase {s['phase']} score {s['score']}")
