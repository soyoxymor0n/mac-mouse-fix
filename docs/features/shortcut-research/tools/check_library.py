#!/usr/bin/env python3
"""Checks the generated ShortcutLibrary.m: key codes, modifier bits, sequences, layout variants, verification data,
and no destructive entries. Also warns about flags in library-flags.json that are marked verified without a source."""
import json, re, sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
path = os.path.join(REPO, "App", "UI", "Main", "Tabs", "ButtonTab", "RemapTable", "ShortcutLibrary.m")
flags_path = os.path.join(HERE, "..", "data", "library-flags.json")
src = open(path, encoding="utf-8").read()

CMD, SHIFT, OPT, CTRL = 0x100000, 0x20000, 0x80000, 0x40000
ALLOWED_FLAGS = CMD | SHIFT | OPT | CTRL
LAYOUTS = ("us", "de", "at")
# Destructive shortcuts, by key code and flags. Q (12) and Escape (53) are on the same key in all checked layouts.
DESTRUCTIVE_KEYS = {
    (12, CMD): "Command+Q (quit)",
    (12, CMD | SHIFT): "Command+Shift+Q (log out)",
    (12, CMD | SHIFT | OPT): "Command+Shift+Option+Q (log out without asking)",
    (53, CMD | OPT): "Command+Option+Escape (force quit)",
    (51, CMD | SHIFT): "Command+Shift+Delete (empty trash)",
    (51, CMD | SHIFT | OPT): "Command+Shift+Option+Delete (empty trash without asking)",
}
DESTRUCTIVE_LABEL = re.compile(r"delete|erase|quit|log ?out|sign ?out|force|empty trash|purchase|unsubscribe", re.I)
STEP = re.compile(r'@\[@(\d+), @(\d+)\]')
STEPS = re.compile(r'@\[(?:@\[@\d+, @\d+\](?:, )?)+\]')
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")

problems = []
warnings = []

apps = re.findall(r'@\{ @"name": @"([^"]+)"', src)
entries = [l.strip() for l in src.splitlines() if l.strip().startswith('@{ @"label": ')]


def field(entry, key):
    m = re.search(r'@"%s": @"((?:[^"\\]|\\.)*)"' % key, entry)
    return m.group(1) if m else None


def label_of(entry):
    m = re.search(r'@"label": (?:NSLocalizedStringWithDefaultValue\(@"[^"]*", nil, NSBundle.mainBundle, )?@"((?:[^"\\]|\\.)*)"', entry)
    return m.group(1) if m else "?"


n_steps = 0
for e in entries:
    label = label_of(e)
    for code, flags in STEP.findall(e):
        n_steps += 1
        code, flags = int(code), int(flags)
        if code > 127:
            problems.append("%s: key code out of range: %d" % (label, code))
        if flags & ~ALLOWED_FLAGS:
            problems.append("%s: unknown modifier bits in flags %d" % (label, flags))
        if (code, flags) in DESTRUCTIVE_KEYS:
            problems.append("%s: destructive shortcut %s" % (label, DESTRUCTIVE_KEYS[(code, flags)]))
    if DESTRUCTIVE_LABEL.search(label):
        problems.append("label looks destructive: %s" % label)

    # Verified entries need their source and date
    if '@"verified": @YES' in e:
        url, day = field(e, "sourceURL"), field(e, "verifiedOn")
        if not url or not url.startswith("http"):
            problems.append("%s: verified without sourceURL" % label)
        if not day or not DATE.match(day):
            problems.append("%s: verified without verifiedOn (YYYY-MM-DD)" % label)

    # Layout-dependent entries have a variant for each layout (or for each layout in `layouts`, when the character can't be typed on the others)
    if '@"layoutDependent": @YES' in e:
        m = re.search(r'@"variants": @\{(.*?)\}', e)
        have = set(re.findall(r'@"(us|de|at)": ', m.group(1))) if m else set()
        lm = re.search(r'@"layouts": @\[([^\]]*)\]', e)
        needed = set(re.findall(r'@"(\w+)"', lm.group(1))) if lm else set(LAYOUTS)
        if not needed <= have:
            problems.append("%s: layout dependent, but variants missing for %s" % (label, sorted(needed - have)))
        if lm and len(needed) < len(LAYOUTS):
            warnings.append("%s: only on %s" % (label, ", ".join(sorted(needed))))

    if '@"suggestedButton"' in e:
        b = re.search(r'@"suggestedButton": @(\d+)', e)
        if not b or not (1 <= int(b.group(1)) <= 32):
            problems.append("%s: suggested button out of range" % label)

# Flags marked verified without a source are shown as not verified by the generator
if os.path.exists(flags_path):
    for f in json.load(open(flags_path, encoding="utf-8")).get("flags", []):
        if f.get("verified") and not (f.get("sourceURL") and DATE.match(str(f.get("verifiedOn", "")))):
            warnings.append("library-flags.json: %s: %s is verified but has no sourceURL and verifiedOn" % (f.get("app"), f.get("action")))

seq_entries = sum(1 for e in entries if re.search(r'@"steps": @\[@\[@\d+, @\d+\], @\[', e))
print("apps:", len(apps), "entries:", len(entries), "steps:", n_steps, "multi-step entries:", seq_entries,
      "layout dependent:", sum(1 for e in entries if '@"layoutDependent": @YES' in e),
      "verified:", sum(1 for e in entries if '@"verified": @YES' in e),
      "in group Other:", sum(1 for e in entries if '@"group": @"Other"' in e))
print("warnings:", len(warnings))
for w in [w for w in warnings if w.startswith("library-flags")]:
    print("  -", w)
print("problems:", len(problems))
for p in problems[:40]:
    print("  -", p)
sys.exit(1 if problems else 0)
