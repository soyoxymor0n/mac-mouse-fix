#!/usr/bin/env python3
"""
Generates App/UI/Main/Tabs/ButtonTab/RemapTable/ShortcutLibrary.m from the shortcut research.

Input:
  - data/shortcuts.json            (research rows for the first apps, each with bundleIDs)
  - data/top100-shortcuts.json     (research rows for the top-100 Mac App Store apps)
  - data/layouts-us-de-at.tsv      (measured key tables: key code and character for US, German, Austrian)
  - data/library-flags.json        (optional: verified, sourceURL, verifiedOn and layouts per entry)
  - data/suggested-mappings.json   (optional: the mouse button the Apps tab suggests for an entry, with a reason)

Every entry that uses a character key (not an arrow, function or other special key) is layout dependent. It stores
one variant per layout (us, de, at), each with its own key codes and flags, resolved from the measured key tables.
A layout where the character can't be typed (or needs a modifier the shortcut already uses) is left out of the
entry's `layouts`, so the entry is hidden there instead of sending the wrong key.

An entry counts as verified only when its flags have `verified`, `sourceURL` and `verifiedOn` (YYYY-MM-DD).

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
SUGGESTIONS_PATH = os.path.join(DATA, "suggested-mappings.json")
LAYOUT_IDS = ("us", "de", "at")
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")

# Labels of the most used entries are localizable (phase 3). (app, action) -> localization key. The English text stays the default.
LOCALIZED_LABELS = {
    ("Google Chrome", "Open the previous page in browsing history for the current tab (alternative)"): "shortcut-library.chrome.back",
    ("Google Chrome", "Open the next page in browsing history for the current tab (alternative)"): "shortcut-library.chrome.forward",
    ("Microsoft Teams", "Toggle mute"): "shortcut-library.teams.mute",
    ("Microsoft Teams", "Toggle video"): "shortcut-library.teams.video",
    ("Visual Studio Code", "New window or instance"): "shortcut-library.vscode.new-window",
}

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
    ("Windows and tabs", re.compile(r"\b(windows?|tabs?|spaces?|mission control|desktop|minimi[sz]e|maximi[sz]e|full[ -]?screen|split view|pin|app exposé|exposé|switch to .*app|switch apps?|applications?)\b", re.I)),
    ("Playback and media", re.compile(r"\b(play|pause|stop|next track|previous track|skip|volume|shuffle|repeat|seek|rewind|fast forward|recording|record|mute|unmute|subtitles|captions|crossfade|reverse|deck|locate track|loop|cue)\b", re.I)),
    ("Search", re.compile(r"\b(find|search|spotlight|filter|look ?up|quick open|go to file|go to line|go to dialog|go to|jump to)\b", re.I)),
    ("Editing", re.compile(r"\b(copy|paste|cut|undo|redo|select all|duplicate|format|bold|italic|underline|strikethrough|indent|outdent|insert|paragraph|comment|uncomment|replace|clear|delete|split|trim|append|clip|formula|highlight|bullet|heading|style|font|align|justify|italics|deselect|^center$|spelling|dictation|password|username)\b", re.I)),
    ("Navigation", re.compile(r"\b(back|forward|next|previous|prev|up|down|left|right|arrow|focus|scroll|page up|page down|home|end|top|bottom|beginning|start of|end of|section|move|jump|row|column|cell|item|field|control|tab key|select|reload|refresh|playhead|navigate|return to the)\b", re.I)),
    ("View and zoom", re.compile(r"\b(zoom|view|sidebar|toolbar|inspector|preview|outline|show|hide|expand|collapse|display|appearance|dark mode|light mode|reader|grid|gallery|actual size|fit|magnif|full screen|toggle|bigger|smaller|thumbnail size)\b", re.I)),
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


def load_json_list(path, key):
    """The list under `key` in a JSON file. A missing or empty file gives an empty list."""
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        return []
    doc = json.load(open(path, encoding="utf-8"))
    return doc.get(key) or []


def load_flags():
    return {(f["app"], f["action"]): {k: v for k, v in f.items() if k not in ("app", "action")} for f in load_json_list(FLAGS_PATH, "flags")}


def load_suggestions():
    """(app, action) -> {"suggestedButton": int, "suggestionReason": str, "suggestionSourceURL": str (optional)}"""
    out = {}
    for sug in load_json_list(SUGGESTIONS_PATH, "suggestions"):
        try:
            button = int(sug["button"])
        except (KeyError, TypeError, ValueError):
            continue
        value = {"suggestedButton": button, "suggestionReason": sug.get("reason", "")}
        if sug.get("sourceURL"):
            value["suggestionSourceURL"] = sug["sourceURL"]
        out[(sug.get("app"), sug.get("action"))] = value
    return out


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
}
# Named symbols are characters, so their key depends on the layout
NAMED_CHARS = {
    "comma": ",", "period": ".", "slash": "/", "semicolon": ";", "quote": "'", "minus": "-",
    "equal": "=", "backslash": "\\", "grave": "`", "left bracket": "[", "right bracket": "]",
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


def is_character_key(key_name):
    """Whether a key is a character, whose key code depends on the layout. Special keys have the same code everywhere."""
    return (key_name or "").strip().lower() not in SPECIAL


def step_for(layout, key_name, mods):
    """(keycode, flags) for one key on one layout. Special keys have the same code everywhere.
    Returns None if the key is unknown, or if typing the character needs a modifier that the shortcut already uses."""
    name = (key_name or "").strip()
    lower = name.lower()
    base = modifier_flags(mods)
    if lower in SPECIAL:
        return (SPECIAL[lower], base)
    ch = NAMED_CHARS.get(lower, name)
    if len(ch) == 1:
        if ch.isalpha():
            ch = ch.lower()
        if ch in SYMBOL_NAMES and layout == "us":
            return (SYMBOL_NAMES[ch], base)
        if ch in LAYOUTS["us"] and LAYOUTS["us"][ch][1] & FLAG["shift"]:
            base &= ~FLAG["shift"]  # the research lists Shift for a shifted character like } or ". The character brings its own modifiers below.
        if ch in LAYOUTS[layout]:
            code, extra = LAYOUTS[layout][ch]
            if extra & base:
                return None  # for example Option+Command+[ on German, where [ itself needs Option
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
    if any(is_character_key(s.get("keyUS", "")) for s in steps_list):
        # Character based: one variant per layout. Layouts where the character can't be typed are left out.
        entry["layoutDependent"] = True
        variants = {}
        for layout in LAYOUT_IDS:
            v = steps_for(steps_list, layout)
            if v is not None:
                variants[layout] = v
        entry["variants"] = variants
        if len(variants) < len(LAYOUT_IDS):
            entry["layouts"] = [l for l in LAYOUT_IDS if l in variants]
    return entry, None


def apply_flags(entry, flags, problems, app_name):
    """Merges the curated flags into an entry. `verified` needs `sourceURL` and `verifiedOn`. Without them it is dropped and reported."""
    if "layouts" in flags:
        allowed = entry.get("layouts", list(LAYOUT_IDS))
        entry["layouts"] = [l for l in flags["layouts"] if l in allowed]
    for key in ("sourceURL", "verifiedOn"):
        if flags.get(key):
            entry[key] = flags[key]
    if flags.get("verified"):
        if entry.get("sourceURL") and DATE.match(str(entry.get("verifiedOn", ""))):
            entry["verified"] = True
        else:
            problems.append("%s: %s (verified, but no sourceURL and verifiedOn: shown as not verified)" % (app_name, entry["label"]))


def objc_string(s):
    return '@"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ") + '"'


def objc_steps(steps):
    return "@[" + ", ".join("@[@%d, @%d]" % (k, f) for k, f in steps) + "]"


def objc_label(e):
    if e.get("labelKey"):
        return "NSLocalizedStringWithDefaultValue(%s, nil, NSBundle.mainBundle, %s, @\"Name of a keyboard shortcut in the shortcut library (Apps tab and the action menu of the Buttons tab).\")" % (
            objc_string(e["labelKey"]), objc_string(e["label"]))
    return objc_string(e["label"])


def objc_entry(e):
    parts = ["@\"label\": " + objc_label(e)]
    if e.get("labelKey"):
        parts.append("@\"labelKey\": " + objc_string(e["labelKey"]))
    parts += ["@\"symbols\": " + objc_string(e["symbols"]), "@\"steps\": " + objc_steps(e["steps"])]
    if e["intervalMs"]:
        parts.append("@\"intervalMs\": @%d" % e["intervalMs"])
    if e.get("layoutDependent"):
        parts.append("@\"layoutDependent\": @YES")
    if e.get("variants"):
        parts.append("@\"variants\": @{" + ", ".join("@\"%s\": %s" % (k, objc_steps(e["variants"][k])) for k in LAYOUT_IDS if k in e["variants"]) + "}")
    if "layouts" in e:
        parts.append("@\"layouts\": @[" + ", ".join(objc_string(l) for l in e["layouts"]) + "]")
    if e.get("verified"):
        parts.append("@\"verified\": @YES")
    if e.get("sourceURL"):
        parts.append("@\"sourceURL\": " + objc_string(e["sourceURL"]))
    if e.get("verifiedOn"):
        parts.append("@\"verifiedOn\": " + objc_string(e["verifiedOn"]))
    if e.get("suggestedButton"):
        parts.append("@\"suggestedButton\": @%d" % e["suggestedButton"])
        parts.append("@\"suggestionReason\": " + objc_string(e.get("suggestionReason", "")))
        if e.get("suggestionSourceURL"):
            parts.append("@\"suggestionSourceURL\": " + objc_string(e["suggestionSourceURL"]))
    parts.append("@\"group\": " + objc_string(e["group"]))
    return "@{ " + ", ".join(parts) + " }"


TEMPLATE = open(os.path.join(HERE, "ShortcutLibrary.template.m"), encoding="utf-8").read()


def main():
    global FLAG_OVERRIDES
    FLAG_OVERRIDES = load_flags()
    suggestions = load_suggestions()
    used_suggestions = set()
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
            if key in apps_out and apps_out[key]["name"] != app["name"]:
                # Two research apps with one bundle ID (Microsoft 365 and Microsoft Word). Mixing them would show
                # unflagged rows under the other app's name, so the first app wins.
                problems.append("%s shares a bundle ID with %s: its shortcuts are skipped" % (app["name"], apps_out[key]["name"]))
                continue
            entries = apps_out.setdefault(key, {"name": app["name"], "bundleIDs": bundles, "entries": []})
            for row in app.get("shortcuts", []):
                if not mouse_suitable(row):
                    continue
                entry, problem = entry_for(row)
                if entry is None:
                    problems.append("%s: %s (%s)" % (app["name"], row.get("action"), problem))
                    continue
                key_ = (app["name"], entry["label"])
                apply_flags(entry, FLAG_OVERRIDES.get(key_, {}), problems, app["name"])
                if key_ in suggestions:
                    entry.update(suggestions[key_])
                    used_suggestions.add(key_)
                if key_ in LOCALIZED_LABELS:
                    entry["labelKey"] = LOCALIZED_LABELS[key_]
                entry["group"] = group_for(app["name"], entry["label"])
                if any(e["label"] == entry["label"] and e["steps"] == entry["steps"] for e in entries["entries"]):
                    continue  # the same action listed twice (for example, a suite page repeating Word's shortcuts)
                entries["entries"].append(entry)

    for key in suggestions:
        if key not in used_suggestions:
            problems.append("suggestion matches no library entry: %s: %s" % key)

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

    kept = [e for a in apps_out.values() for e in a["entries"]]
    print("apps in library:", kept_apps, "entries:", kept_entries)
    print("layout dependent:", sum(1 for e in kept if e.get("layoutDependent")),
          "| hidden on some layout:", sum(1 for e in kept if "layouts" in e and len(e["layouts"]) < len(LAYOUT_IDS)),
          "| verified:", sum(1 for e in kept if e.get("verified")),
          "| with suggestion:", sum(1 for e in kept if e.get("suggestedButton")),
          "| localized labels:", sum(1 for e in kept if e.get("labelKey")),
          "| in group Other:", sum(1 for e in kept if e["group"] == "Other"))
    print("problems:", len(problems))
    for p in problems[:80]:
        print("  -", p)
    if len(problems) > 80:
        print("  ... %d more" % (len(problems) - 80))
    print("written:", OUT)


if __name__ == "__main__":
    sys.exit(main())
