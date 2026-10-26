#!/usr/bin/env python3
"""Checks the generated ShortcutLibrary.m: key codes, modifier bits, sequences, and no destructive entries."""
import re, sys, os
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))
path = os.path.join(REPO, "App", "UI", "Main", "Tabs", "ButtonTab", "RemapTable", "ShortcutLibrary.m")
src = open(path, encoding="utf-8").read()
ALLOWED_FLAGS = 0x100000 | 0x20000 | 0x80000 | 0x40000  # cmd, shift, option, control
problems = []
apps = re.findall(r'@\{ @"name": @"([^"]+)"', src)
steps = re.findall(r'@\[@(\d+), @(\d+)\]', src)
for code, flags in steps:
    if int(code) > 127:
        problems.append("key code out of range: %s" % code)
    if int(flags) & ~ALLOWED_FLAGS:
        problems.append("unknown modifier bits in flags %s" % flags)
seq_entries = len(re.findall(r'@"steps": @\[@\[@\d+, @\d+\], @\[', src))
labels = re.findall(r'@"label": @"([^"]+)"', src)
bad = [l for l in labels if re.search(r"delete|erase|quit|log ?out|sign ?out|force|empty trash|purchase|unsubscribe", l, re.I)]
if bad:
    problems.append("labels that look destructive: %s" % bad[:10])
print("apps:", len(apps), "entries:", len(labels), "steps:", len(steps), "multi-step entries:", seq_entries)
print("problems:", len(problems))
for p in problems[:40]:
    print("  -", p)
sys.exit(1 if problems else 0)
