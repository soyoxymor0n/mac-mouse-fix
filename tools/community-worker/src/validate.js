// Validation of community setup submissions. No Worker APIs, so `node --test` can import it.
// Same rules as the app (App/UI/Main/Tabs/ButtonTab/AppTabs/CommunitySetups.swift and CommunitySharing.swift)
// and as scripts/validate.py in the setups repository, which is the source of truth for the file format.

export const SCHEMA_VERSION = 1;
export const MAX_ROWS = 20;
export const MAX_BYTES = 16 * 1024;
export const LICENSE = "CC0-1.0";
/** Command, Shift, Control and Option */
export const FLAG_MASK = 0x1e0000;

export const TITLES = ["Mic and camera", "Browser navigation", "Tab switching", "Finder navigation", "Other"];

/** Command+Q, Command+Shift+Q and Command+Option+Escape (force quit) */
export const DENYLIST = [
  { keycode: 12, flags: 0x100000 },
  { keycode: 12, flags: 0x120000 },
  { keycode: 53, flags: 0x180000 },
];

// Apps whose bundle ID can reveal health, dating, religious, political or financial information.
// Keep these two lists equal to CommunitySensitiveApps in CommunitySharing.swift; test/sync.test.js checks it.
// The owner can extend both. Matching is case-insensitive.

/** A bundle ID that equals one of these, or starts with one followed by a dot, is refused */
export const SENSITIVE_BUNDLE_ID_PREFIXES = [
  "com.apple.health",
  "com.cardify.tinder",
  "com.bumble",
  "co.hinge",
  "com.grindr",
  "com.okcupid",
  "com.match",
  "com.headspace",
  "com.calm",
  "com.betterhelp",
  "com.talkspace",
  "com.youversion",
  "com.muslimpro",
  "com.intuit",
  "com.paypal",
  "com.coinbase",
  "com.binance",
  "com.robinhood",
  "com.revolut",
  "de.number26",
  "com.moneymoney-app",
  "com.ledger",
];

/** A bundle ID that contains one of these anywhere is refused */
export const SENSITIVE_KEYWORDS = [
  "bank",
  "dating",
  "bible",
  "quran",
  "church",
  "mosque",
  "prayer",
  "health",
  "medical",
  "therapy",
  "fertility",
  "crypto",
  "bitcoin",
  "wallet",
  "election",
  "politic",
];

const BUNDLE_ID = /^[A-Za-z0-9.-]{3,200}$/;
const TOP_KEYS = ["schemaVersion", "bundleID", "title", "rows"];
const ROW_KEYS = ["trigger", "modifiers", "effect", "app"];
const TRIGGER_KEYS = ["button", "duration", "level"];
const EFFECT_KEYS = ["type", "keycode", "flags"];

function isPlainObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasOnlyKeys(object, allowed) {
  return Object.keys(object).every((key) => allowed.includes(key));
}

function hasExactlyKeys(object, keys) {
  const own = Object.keys(object);
  return own.length === keys.length && keys.every((key) => own.includes(key));
}

function isInt(value) {
  return typeof value === "number" && Number.isInteger(value);
}

export function isSensitiveBundleID(bundleID) {
  const id = String(bundleID).toLowerCase();
  if (SENSITIVE_BUNDLE_ID_PREFIXES.some((prefix) => id === prefix || id.startsWith(prefix + "."))) return true;
  return SENSITIVE_KEYWORDS.some((keyword) => id.includes(keyword));
}

export function isDenied(keycode, flags) {
  return DENYLIST.some((entry) => entry.keycode === keycode && entry.flags === flags);
}

/**
 * Checks one row. Returns the row rebuilt from the checked values (only the allowed keys), or null.
 */
export function validRow(row, bundleID) {
  if (!isPlainObject(row) || !hasOnlyKeys(row, ROW_KEYS)) return null;
  if (row.app !== bundleID) return null;
  if (!isPlainObject(row.modifiers) || Object.keys(row.modifiers).length !== 0) return null;

  const trigger = row.trigger;
  if (!isPlainObject(trigger) || !hasExactlyKeys(trigger, TRIGGER_KEYS)) return null;
  if (!isInt(trigger.button) || trigger.button < 1 || trigger.button > 5) return null;
  if (trigger.duration !== "click" && trigger.duration !== "hold") return null;
  if (!isInt(trigger.level) || trigger.level < 1 || trigger.level > 3) return null;

  const effect = row.effect;
  if (!isPlainObject(effect) || !hasExactlyKeys(effect, EFFECT_KEYS)) return null;
  if (effect.type !== "keyboardShortcut") return null;
  if (!isInt(effect.keycode) || effect.keycode < 0 || effect.keycode > 127) return null;
  // JavaScript's bitwise operators work on 32 bits, so the upper bound is checked first
  if (!isInt(effect.flags) || effect.flags < 0 || effect.flags > FLAG_MASK || (effect.flags & ~FLAG_MASK) !== 0) return null;
  if (isDenied(effect.keycode, effect.flags)) return null;

  return {
    trigger: { button: trigger.button, duration: trigger.duration, level: trigger.level },
    modifiers: {},
    effect: { type: "keyboardShortcut", keycode: effect.keycode, flags: effect.flags },
    app: bundleID,
  };
}

/**
 * Checks a parsed submission. Every row must pass; unlike the download, no row is left out silently.
 * Returns { ok: true, submission } with a copy that holds only the allowed keys, or { ok: false, errors }.
 */
export function validateSubmission(object) {
  if (!isPlainObject(object)) return { ok: false, errors: ["top level must be an object"] };
  const errors = [];
  if (!hasOnlyKeys(object, TOP_KEYS)) errors.push("unknown top-level keys");
  if (object.schemaVersion !== SCHEMA_VERSION) errors.push("schemaVersion must be 1");
  const bundleID = object.bundleID;
  if (typeof bundleID !== "string" || !BUNDLE_ID.test(bundleID)) {
    errors.push("bundleID must match [A-Za-z0-9.-]{3,200}");
  } else if (isSensitiveBundleID(bundleID)) {
    errors.push("apps with sensitive purposes can't be shared");
  }
  if (!TITLES.includes(object.title)) errors.push("title must be one of the fixed list");
  const rows = object.rows;
  if (!Array.isArray(rows) || rows.length < 1 || rows.length > MAX_ROWS) {
    errors.push(`rows must be a list of 1 to ${MAX_ROWS} entries`);
  }
  if (errors.length > 0) return { ok: false, errors };

  const checked = [];
  rows.forEach((row, i) => {
    const valid = validRow(row, bundleID);
    if (valid) checked.push(valid);
    else errors.push(`rows[${i}] breaks a rule`);
  });
  if (errors.length > 0) return { ok: false, errors };

  return { ok: true, submission: { schemaVersion: SCHEMA_VERSION, bundleID, title: object.title, rows: checked } };
}
