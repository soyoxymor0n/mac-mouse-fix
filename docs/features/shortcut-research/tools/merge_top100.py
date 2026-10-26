#!/usr/bin/env python3
"""Merges the per-batch research outputs for the top-100 apps into data/top100-shortcuts.json and keeps the ranked list."""
import glob, json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "..", "data")
src_dir = sys.argv[1]
apps, seen = [], set()
for path in sorted(glob.glob(os.path.join(src_dir, "out", "top100-*.json"))):
    doc = json.load(open(path, encoding="utf-8"))
    for app in doc.get("apps", []):
        if app["name"] in seen:
            continue
        seen.add(app["name"])
        apps.append(app)
json.dump({"generated": "2026-10-26", "source": "top-100 Mac App Store free chart, iOS-tagged entries excluded", "apps": apps},
          open(os.path.join(DATA, "top100-shortcuts.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
ranked = json.load(open(os.path.join(src_dir, "top100.json"), encoding="utf-8"))
json.dump(ranked, open(os.path.join(DATA, "top100-ranked.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("merged apps:", len(apps), "shortcut rows:", sum(len(a.get("shortcuts", [])) for a in apps))
