#!/usr/bin/env python3
"""
Generates App/UI/Main/Tabs/ButtonTab/RemapTable/ShortcutLibrary.m from the shortcut research.

Input:
  - data/shortcuts.json            (research rows for the first apps, each with bundleIDs)
  - data/top100-shortcuts.json     (research rows for the top-100 Mac App Store apps)
  - data/layouts-us-de-at.tsv      (measured key tables: key code and character for US, German, Austrian)

Only rows with mouseSuitable == true and destructive == false are used. Rows with unknown key names are
reported and skipped. Apps without a verified bundle ID are reported and skipped.

Run: python3 docs/features/shortcut-research/tools/gen_library.py
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "..", "data")
REPO = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
OUT = os.path.join(REPO, "App", "UI", "Main", "Tabs", "ButtonTab", "RemapTable", "ShortcutLibrary.m")
FLAGS_PATH = os.path.join(DATA, "library-flags.json")

# Bundle IDs read from the Info.plist of the installed apps on the owner's Mac (2026-10-26), for apps whose research row says "unverified".
BUNDLE_OVERRIDES = {
    "Finder": ["com.apple.finder"], "Mail": ["com.apple.mail"], "Messages": ["com.apple.MobileSMS"],
    "Calendar": ["com.apple.iCal"], "Notes": ["com.apple.Notes"], "Photos": ["com.apple.Photos"],
    "Music": ["com.apple.Music"], "Preview": ["com.apple.Preview"], "Terminal": ["com.apple.Terminal"],
    "Safari": ["com.apple.Safari"], "Microsoft Teams": ["com.microsoft.teams2"],
}

# A row counts as mouse-suitable if the research flag says so, or if its action is a single toggle or navigation
# step (mute, camera, raise hand, back, forward, tab, new tab, play, undo, and similar). Destructive wording always excludes.
MOUSE_WORDS = re.compile(r"\b(back|forward|tab|reload|refresh|mute|unmute|camera|video|share|record|raise|hand|search|next|previous|play|pause|undo|redo|copy|paste|screenshot|zoom in|zoom out|new tab|new window|mission control|enclosing|parent folder|toggle|reaction)\b", re.I)
DESTRUCTIVE_WORDS = re.compile(r"\b(delete|remove|quit|log ?out|sign ?out|erase|empty|force|close all|purchase|unsubscribe|uninstall)\b", re.I)
HOLD_WORDS = re.compile(r"\(hold\)|\bhold down\b|\bwhile holding\b", re.I)


def mouse_suitable(row):
    action = row.get("action", "")
    if DESTRUCTIVE_WORDS.search(action) or row.get("destructive"):
        return False
    if HOLD_WORDS.search(action):
        return False  # a remap effect presses and releases the keys at once, so it can't hold a key down
    return bool(row.get("mouseSuitable")) or bool(MOUSE_WORDS.search(action))


# Shortcut groups. The default groups are shown for every app, in this order. Each entry gets one group.
# A group is a default group, or a specific group that only some apps have (see SPECIFIC_GROUPS).
DEFAULT_GROUPS = ["Windows and tabs", "Playback and media", "Search", "Editing", "Navigation", "View and zoom", "File", "Other"]

# Specific groups, checked before the default groups. Each rule: (group, app-name pattern, label pattern).
SPECIFIC_GROUPS = [
    ("Calls and meetings", re.compile(r"Teams|Zoom|Slack|Discord|FaceTime", re.I),
     re.compile(r"\b(call|meeting|mute|unmute|camera|video|hand|reaction|caption|screen share|share|leave|record|participant)", re.I)),
    ("Messages", re.compile(r"Teams|Slack|Discord|Messages|Mail|WhatsApp|Telegram", re.I),
     re.compile(r"\b(message|reply|forward|compose|conversation|thread|mention|chat|send|draft|DMs?|direct messages?)", re.I)),
    ("Bookmarks and history", re.compile(r"Chrome|Safari|Firefox|Brave|Edge|Arc|Opera|Vivaldi", re.I),
     re.compile(r"\b(bookmark|history|downloads?|favorites?|reading list)", re.I)),
]

# Default groups: the first pattern that matches the label wins. Order matters.
DEFAULT_RULES = [
    ("Windows and tabs", re.compile(r"\b(windows?|tabs?|spaces?|mission control|desktop|minimi[sz]e|maximi[sz]e|full ?screen|split view|pin|app exposé|exposé|switch to .*app|switch apps?|applications?)\b", re.I)),
    ("Playback and media", re.compile(r"\b(play|pause|stop|next track|previous track|skip|volume|shuffle|repeat|seek|rewind|fast forward|recording|record|mute|unmute|subtitles|captions|crossfade|reverse|deck|locate track|loop|cue)\b", re.I)),
    ("Search", re.compile(r"\b(find|search|spotlight|filter|look ?up|quick open|go to file|go to line|go to dialog|go to|jump to)\b", re.I)),
    ("Editing", re.compile(r"\b(copy|paste|cut|undo|redo|select all|duplicate|format|bold|italic|underline|strikethrough|indent|outdent|insert|paragraph|comment|uncomment|replace|clear|delete|split|trim|append|clip|formula|highlight|bullet|heading|style|font|align|spelling|dictation|password|username)\b", re.I)),
    ("Navigation", re.compile(r"\b(back|forward|next|previous|prev|up|down|left|right|arrow|focus|scroll|page up|page down|home|end|top|bottom|beginning|start of|end of|section|move|jump|row|column|cell|item|field|control|tab key|select|reload|refresh|playhead)\b", re.I)),
    ("View and zoom", re.compile(r"\b(zoom|view|sidebar|toolbar|inspector|preview|outline|show|hide|expand|collapse|display|appearance|dark mode|light mode|reader|grid|gallery|actual size|fit|magnif|full screen|toggle)\b", re.I)),
    ("File", re.compile(r"\b(new|open|save|print|export|import|share|rename|file|document|folder|close|quit|page setup|archive|upload|download|attach|page)\b", re.I)),
]


def group_for(app_name, label):
    """Returns the group of an entry: a specific group if one applies, otherwise the first default group that matches, otherwise Other."""
    for group, app_pattern, label_pattern in SPECIFIC_GROUPS:
        if app_pattern.search(app_name) and label_pattern.search(label):
            return group
    for group, pattern in DEFAULT_RULES:
        if pattern.search(label):
            return group
    return "Other"


def load_flags():
    if not os.path.exists(FLAGS_PATH):
        return {}
    doc = json.load(open(FLAGS_PATH, encoding="utf-8"))
    return {(f["app"], f["action"]): {k: v for k, v in f.items() if k not in ("app", "action")} for f in doc.get("flags", [])}


FLAG = {"cmd": 1048576, "shift": 131072, "opt": 524288, "ctrl": 262144}

SPECIAL = {
    "left arrow": 123, "right arrow": 124, "down arrow": 125, "up arrow": 126,
    "left": 123, "right": 124, "down": 125, "up": 126,
    "return": 36, "enter": 76, "tab": 48, "space": 49, "delete": 51, "backspace": 51,
    "forward delete": 117, "escape": 53, "esc": 53, "home": 115, "end": 119,
    "page up": 116, "page down": 121,
    "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
    "f9": 101, "f10": 109, "f11": 103, "f12": 111, "f14": 107,
    "comma": 43, "period": 47, "slash": 44, "semicolon": 41, "quote": 39, "minus": 27,
    "equal": 24, "backslash": 42, "grave": 50, "left bracket": 33, "right bracket": 30,
}
SYMBOL_NAMES = {
    ",": 43, ".": 47, "/": 44, ";": 41, "'": 39, "-": 27, "=": 24, "\\": 42, "`": 50, "[": 33, "]": 30,
}


def load_layout(name):
    """Returns {(char): (keycode, extra_flags)} for a layout, preferring the plain character, then shift, option, option+shift."""
    table = {}
    path = os.path.join(DATA, "layouts-us-de-at.tsv")
    section = None
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if line.startswith("## "):
                section = line[3:].strip()
                continue
            if not section or line.startswith("keycode") or not line:
                continue
            parts = line.split("\t")
            if len(parts) < 5 or not parts[0].isdigit():
                continue
            if section != name:
                continue
            code = int(parts[0])
            cols = [(parts[1], 0), (parts[2], FLAG["shift"]), (parts[3], FLAG["opt"]), (parts[4], FLAG["shift"] | FLAG["opt"])]
            for ch, extra in cols:
                if len(ch) == 1 and ch not in ("-", " ") and ch not in table:
                    table[ch] = (code, extra)
    return table


LAYOUTS = {
    "us": load_layout("com.apple.keylayout.US"),
    "de": load_layout("com.apple.keylayout.German"),
    "at": load_layout("com.apple.keylayout.Austrian"),
}


def modifier_flags(mods):
    flags = 0
    for m in mods or []:
        if m not in FLAG:
            raise ValueError("unknown modifier " + str(m))
        flags |= FLAG[m]
    return flags


def step_for(layout, key_name, mods):
    """(keycode, flags) for one key on one layout. Special keys have the same code everywhere. Returns None if unknown."""
    name = (key_name or "").strip()
    lower = name.lower()
    base = modifier_flags(mods)
    if lower in SPECIAL:
        return (SPECIAL[lower], base)
    if len(name) == 1:
        ch = name
        if ch.isalpha():
            ch = ch.lower()
        if ch in SYMBOL_NAMES and layout == "us":
            return (SYMBOL_NAMES[ch], base)
        if ch in LAYOUTS[layout]:
            code, extra = LAYOUTS[layout][ch]
            return (code, base | extra)
    return None


def steps_for(row_steps, layout):
    out = []
    for s in row_steps:
        r = step_for(layout, s.get("keyUS", ""), s.get("modifiers", []))
        if r is None:
            return None
        out.append(r)
    return out


def entry_for(row):
    """Builds the library entry for one research row. Returns (entry, problem)."""
    kind = row.get("kind", "shortcut")
    if kind == "sequence":
        raw_steps = row.get("steps") or []
        if len(raw_steps) < 2:
            return None, "sequence without two steps"
        steps_list = raw_steps
    else:
        steps_list = [{"keyUS": row.get("keyUS", ""), "modifiers": row.get("modifiers", [])}]

    us = steps_for(steps_list, "us")
    if us is None:
        return None, "unknown key: " + repr([s.get("keyUS") for s in steps_list])
    entry = {
        "label": row["action"],
        "symbols": row.get("symbols", ""),
        "steps": us,
        "intervalMs": 120 if kind == "sequence" else 0,
    }
    variants = {}
    for layout in ("de", "at"):
        alt = steps_for(steps_list, layout)
        if alt is not None and alt != us:
            variants[layout] = alt
    if variants:
        entry["variants"] = variants
    return entry, None


def objc_string(s):
    return '@"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ") + '"'


def objc_steps(steps):
    return "@[" + ", ".join("@[@%d, @%d]" % (k, f) for k, f in steps) + "]"


def objc_entry(e):
    parts = ["@\"label\": " + objc_string(e["label"]), "@\"symbols\": " + objc_string(e["symbols"]),
             "@\"steps\": " + objc_steps(e["steps"])]
    if e["intervalMs"]:
        parts.append("@\"intervalMs\": @%d" % e["intervalMs"])
    if e.get("variants"):
        parts.append("@\"variants\": @{" + ", ".join("@\"%s\": %s" % (k, objc_steps(v)) for k, v in sorted(e["variants"].items())) + "}")
    if e.get("layouts"):
        parts.append("@\"layouts\": @[" + ", ".join(objc_string(l) for l in e["layouts"]) + "]")
    if e.get("verified"):
        parts.append("@\"verified\": @YES")
    parts.append("@\"group\": " + objc_string(e["group"]))
    return "@{ " + ", ".join(parts) + " }"


TEMPLATE = open(os.path.join(HERE, "ShortcutLibrary.template.m"), encoding="utf-8").read()


def main():
    global FLAG_OVERRIDES
    FLAG_OVERRIDES = load_flags()
    rows = []
    apps_out = {}
    problems = []
    for fname in ["shortcuts.json", "top100-shortcuts.json"]:
        path = os.path.join(DATA, fname)
        if not os.path.exists(path):
            continue
        doc = json.load(open(path, encoding="utf-8"))
        for app in doc.get("apps", []):
            bundles = [b for b in app.get("bundleIDs", []) if b and b != "unverified"]
            if not bundles and app["name"] in BUNDLE_OVERRIDES:
                bundles = BUNDLE_OVERRIDES[app["name"]]
            if not bundles:
                problems.append("no verified bundle ID: " + app["name"])
                continue
            key = bundles[0]
            entries = apps_out.setdefault(key, {"name": app["name"], "bundleIDs": bundles, "entries": []})
            for row in app.get("shortcuts", []):
                if not mouse_suitable(row):
                    continue
                entry, problem = entry_for(row)
                if entry is None:
                    problems.append("%s: %s (%s)" % (app["name"], row.get("action"), problem))
                    continue
                entry.update(FLAG_OVERRIDES.get((app["name"], entry["label"]), {}))
                entry["group"] = group_for(app["name"], entry["label"])
                if any(e["label"] == entry["label"] and e["steps"] == entry["steps"] for e in entries["entries"]):
                    continue  # the same action listed twice (for example, a suite page repeating Word's shortcuts)
                entries["entries"].append(entry)

    blocks = []
    kept_apps = 0
    kept_entries = 0
    for key in sorted(apps_out, key=lambda k: apps_out[k]["name"].lower()):
        app = apps_out[key]
        if not app["entries"]:
            continue
        kept_apps += 1
        kept_entries += len(app["entries"])
        entries_text = ",\n".join("                " + objc_entry(e) for e in app["entries"])
        blocks.append("            @{ @\"name\": %s,\n               @\"bundleIDs\": @[%s],\n               @\"entries\": @[\n%s\n               ] },"
                      % (objc_string(app["name"]), ", ".join(objc_string(b) for b in app["bundleIDs"]), entries_text))

    text = TEMPLATE.replace("__APPS__", "\n".join(blocks)).replace("__DEFAULT_GROUPS__", ", ".join(objc_string(g) for g in DEFAULT_GROUPS))
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(text)

    print("apps in library:", kept_apps, "entries:", kept_entries)
    print("problems:", len(problems))
    for p in problems[:80]:
        print("  -", p)
    if len(problems) > 80:
        print("  ... %d more" % (len(problems) - 80))
    print("written:", OUT)


if __name__ == "__main__":
    sys.exit(main())
