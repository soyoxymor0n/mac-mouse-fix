#!/usr/bin/env python3
"""Writes top100.md: the ranked top-100 Mac App Store free apps with research status, counts, and library membership."""
import json, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_library import mouse_suitable
HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "..", "data")
ranked = json.load(open(os.path.join(DATA, "top100-ranked.json"), encoding="utf-8"))
research = {}
for fname in ["shortcuts.json", "top100-shortcuts.json"]:
    doc = json.load(open(os.path.join(DATA, fname), encoding="utf-8"))
    for a in doc["apps"]:
        research.setdefault(a["name"].lower(), a)
src = open(os.path.join(HERE, "..", "..", "..", "..", "App", "UI", "Main", "Tabs", "ButtonTab", "RemapTable", "ShortcutLibrary.m"), encoding="utf-8").read()
library_names = set(re.findall(r'@\{ @"name": @"([^"]+)"', src))
lines = ["# Top 100 Mac App Store free apps: shortcut research", "",
         "Source: the Top Free chart of the Mac App Store (Austrian storefront, read on 2026-10-25/26). iOS-tagged entries are excluded, so the first 100 Mac entries run to rank 106. Bundle IDs marked unverified were not confirmed.",
         "",
         "- Research status: complete, partial (some rows missing), no-official-source (the vendor has no Mac shortcut page), or not-researched.",
         "- Mouse suitable: rows that suit a mouse button (toggles, navigation, tabs, undo and similar), after the generator's rules.",
         "- In library: the app has at least one mouse-suitable entry in ShortcutLibrary.m.",
         "",
         "| Rank | App | Bundle ID | Research | Shortcuts | Mouse suitable | Sequences | In library |",
         "|---|---|---|---|---|---|---|---|"]
for r in ranked:
    name = r["name"]
    rec = research.get(name.lower())
    if rec is None:
        for key, val in research.items():
            if key.startswith(name.lower()[:12]) or name.lower().startswith(key[:12]):
                rec = val
                break
    status = rec.get("status", "") if rec else "not-researched"
    rows = rec.get("shortcuts", []) if rec else []
    mouse = sum(1 for x in rows if mouse_suitable(x))
    seqs = sum(1 for x in rows if x.get("kind") == "sequence")
    bundle = r.get("bundleId") or ((rec or {}).get("bundleIDs") or [""])[0] or "unverified"
    in_lib = "yes" if name in library_names or (rec and rec["name"] in library_names) else ""
    lines.append("| %s | %s | %s | %s | %d | %d | %d | %s |" % (r["rank"], name, bundle, status, len(rows), mouse, seqs, in_lib))
open(os.path.join(HERE, "..", "top100.md"), "w", encoding="utf-8").write("\n".join(lines) + "\n")
print("wrote top100.md with", len(ranked), "rows")
