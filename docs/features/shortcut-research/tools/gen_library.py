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

# Bundle IDs read from the Info.plist of the installed apps on the owner's Mac (2026-10-26), for apps whose research row says "unverified".
BUNDLE_OVERRIDES = {
    "Finder": ["com.apple.finder"], "Mail": ["com.apple.mail"], "Messages": ["com.apple.MobileSMS"],
    "Calendar": ["com.apple.iCal"], "Notes": ["com.apple.Notes"], "Photos": ["com.apple.Photos"],
    "Music": ["com.apple.Music"], "Preview": ["com.apple.Preview"], "Terminal": ["com.apple.Terminal"],
    "Safari": ["com.apple.Safari"], "Microsoft Teams": ["com.microsoft.teams2"],
}

# A row counts as mouse-suitable if the research flag says so, or if its action is a single toggle or navigation
# step (mute, camera, raise hand, back, forward, tab, new tab, play, undo, and similar). Destructive wording always excludes.
MOUSE_WORDS = re.compile(r"\b(back|forward|tab|reload|refresh|mute|unmute|camera|video|share|record|raise|hand|search|next|previous|play|pause|undo|redo|copy|paste|screenshot|zoom in|zoom out|new tab|new window|mission control|enclosing|parent folder|toggle)\b", re.I)
DESTRUCTIVE_WORDS = re.compile(r"\b(delete|remove|quit|log ?out|sign ?out|erase|empty|force|close all|purchase|unsubscribe|uninstall)\b", re.I)


def mouse_suitable(row):
    action = row.get("action", "")
    if DESTRUCTIVE_WORDS.search(action) or row.get("destructive"):
        return False
    return bool(row.get("mouseSuitable")) or bool(MOUSE_WORDS.search(action))


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
    return "@{ " + ", ".join(parts) + " }"


TEMPLATE = """//
// --------------------------------------------------------------------------
// ShortcutLibrary.m
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License)
// --------------------------------------------------------------------------
//
// GENERATED by docs/features/shortcut-research/tools/gen_library.py. Do not edit by hand.
// Source: the shortcut research in docs/features/shortcut-research (mouse-suitable rows only, checked against vendor documentation).

#import "ShortcutLibrary.h"
#import "Constants.h"
#import "Mac_Mouse_Fix-Swift.h"
#import <Carbon/Carbon.h>

@implementation ShortcutLibrary

/// Library data. Each app has its bundle IDs and entries.
/// Each entry has a label, the symbols shown as a hint, the steps as [keycode, flags] for the US layout,
/// optional `variants` for the German and Austrian layouts, and `intervalMs` for sequences (steps with more than one key).
+ (NSArray *)apps {
    static NSArray *apps;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        apps = @[
__APPS__
        ];
    });
    return apps;
}

/// The layout the user types with. German and Austrian have their own variants, everything else uses US.
+ (NSString *)activeLayoutID {
    TISInputSourceRef source = TISCopyCurrentKeyboardLayoutInputSource();
    NSString *ident = nil;
    if (source != NULL) {
        ident = (__bridge NSString *)TISGetInputSourceProperty(source, kTISPropertyInputSourceID);
        CFRelease(source);
    }
    if ([ident isEqualToString:@"com.apple.keylayout.German"]) return @"de";
    if ([ident isEqualToString:@"com.apple.keylayout.Austrian"]) return @"at";
    return @"us";
}

+ (NSArray *)effectsMenuEntriesForBundleID:(NSString *)bundleID {
    NSString *layout = [self activeLayoutID];
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *app in [self apps]) {
        if (![app[@"bundleIDs"] containsObject:bundleID]) continue;
        for (NSDictionary *entry in app[@"entries"]) {
            NSArray *steps = entry[@"variants"][layout] ?: entry[@"steps"];
            [result addObject:[self menuEntryForLabel:entry[@"label"]
                                              symbols:entry[@"symbols"]
                                                steps:steps
                                           intervalMs:[entry[@"intervalMs"] doubleValue]]];
        }
    }
    return result;
}

/// One effect-menu entry. A single key is a keyboardShortcut effect. Several keys are a keySequence effect.
+ (NSDictionary *)menuEntryForLabel:(NSString *)label symbols:(NSString *)symbols steps:(NSArray *)steps intervalMs:(double)intervalMs {
    NSDictionary *dict;
    if (steps.count == 1) {
        dict = @{
            kMFActionDictKeyType: kMFActionDictTypeKeyboardShortcut,
            kMFActionDictKeyKeyboardShortcutVariantKeycode: steps[0][0],
            kMFActionDictKeyKeyboardShortcutVariantModifierFlags: steps[0][1],
        };
    } else {
        NSMutableArray *stepDicts = [NSMutableArray array];
        for (NSArray *step in steps) {
            [stepDicts addObject:@{
                kMFActionDictKeyKeyboardShortcutVariantKeycode: step[0],
                kMFActionDictKeyKeyboardShortcutVariantModifierFlags: step[1],
            }];
        }
        dict = @{
            kMFActionDictKeyType: kMFActionDictTypeKeySequence,
            kMFActionDictKeySequenceVariantSteps: stepDicts,
            kMFActionDictKeySequenceVariantIntervalMs: @(intervalMs > 0 ? intervalMs : 120),
        };
    }
    return @{ @"ui": label, @"tool": symbols, @"dict": dict };
}

@end
"""


def main():
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

    text = TEMPLATE.replace("__APPS__", "\n".join(blocks))
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
