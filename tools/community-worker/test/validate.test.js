import { test } from "node:test";
import assert from "node:assert/strict";
import { validateSubmission, validRow, isSensitiveBundleID, isDenied, MAX_ROWS } from "../src/validate.js";

const chrome = "com.google.Chrome";

function row({ button = 4, duration = "click", level = 1, type = "keyboardShortcut", keycode = 13, flags = 0x100000, app = chrome } = {}) {
  return { trigger: { button, duration, level }, modifiers: {}, effect: { type, keycode, flags }, app };
}

function submission(overrides = {}) {
  return { schemaVersion: 1, bundleID: chrome, title: "Tab switching", rows: [row()], ...overrides };
}

test("a valid submission passes and is copied with the allowed keys only", () => {
  const result = validateSubmission(submission({ rows: [row(), row({ button: 5, duration: "hold", level: 3, keycode: 127, flags: 0x1e0000 })] }));
  assert.equal(result.ok, true);
  assert.deepEqual(Object.keys(result.submission).sort(), ["bundleID", "rows", "schemaVersion", "title"]);
  assert.equal(result.submission.rows.length, 2);
});

test("row rules match the app and validate.py", () => {
  assert.ok(validRow(row(), chrome));
  assert.equal(validRow(row({ keycode: 128 }), chrome), null, "keycode 128");
  assert.equal(validRow(row({ keycode: -1 }), chrome), null, "negative keycode");
  assert.equal(validRow(row({ keycode: 13.5 }), chrome), null, "fraction");
  assert.equal(validRow(row({ keycode: true }), chrome), null, "boolean keycode");
  assert.equal(validRow(row({ flags: 0x100000 | 0x800000 }), chrome), null, "flag outside the mask");
  assert.equal(validRow(row({ flags: 1 }), chrome), null, "low flag bit");
  assert.equal(validRow(row({ flags: 2 ** 32 + 0x100000 }), chrome), null, "flags above 32 bits");
  assert.equal(validRow(row({ type: "symbolicHotkey" }), chrome), null, "effect type");
  assert.equal(validRow(row({ button: 6 }), chrome), null, "button 6");
  assert.equal(validRow(row({ duration: "double" }), chrome), null, "duration");
  assert.equal(validRow(row({ level: 4 }), chrome), null, "level 4");
  assert.equal(validRow(row({ app: "com.apple.finder" }), chrome), null, "other app");
  assert.equal(validRow({ ...row(), license: "x" }, chrome), null, "unknown row key");
  assert.equal(validRow({ ...row(), modifiers: { buttonModifiers: [] } }, chrome), null, "modifiers");
  assert.equal(validRow({ ...row(), effect: { type: "keyboardShortcut", keycode: 13, flags: 0x100000, script: "x" } }, chrome), null, "unknown effect key");
});

test("denylisted key combinations are refused", () => {
  assert.ok(isDenied(12, 0x100000));
  assert.ok(isDenied(12, 0x120000));
  assert.ok(isDenied(53, 0x180000));
  assert.ok(!isDenied(12, 0x40000));
  assert.equal(validateSubmission(submission({ rows: [row(), row({ keycode: 12, flags: 0x100000 })] })).ok, false);
});

test("top-level rules", () => {
  assert.equal(validateSubmission(submission({ schemaVersion: 2 })).ok, false, "schemaVersion");
  assert.equal(validateSubmission(submission({ title: "My setup" })).ok, false, "free-text title");
  assert.equal(validateSubmission(submission({ bundleID: "a b" })).ok, false, "bundle ID");
  assert.equal(validateSubmission(submission({ rows: [] })).ok, false, "no rows");
  assert.equal(validateSubmission(submission({ rows: Array(MAX_ROWS + 1).fill(row()) })).ok, false, "21 rows");
  assert.equal(validateSubmission(submission({ rows: Array(MAX_ROWS).fill(row()) })).ok, true, "20 rows");
  assert.equal(validateSubmission({ ...submission(), appVersion: "3.0" }).ok, false, "extra key");
  assert.equal(validateSubmission([]).ok, false, "array");
  assert.equal(validateSubmission(null).ok, false, "null");
});

test("sensitive apps are refused", () => {
  for (const id of ["com.apple.Health", "com.cardify.tinder", "com.bumble.app", "com.intuit.QuickBooks", "com.example.MyBank", "org.example.BibleReader",
    "com.example.cryptowallet", "com.example.Dating", "com.example.ElectionTracker", "COM.PAYPAL.desktop"]) {
    assert.ok(isSensitiveBundleID(id), id);
  }
  for (const id of ["com.google.Chrome", "com.microsoft.teams2", "com.apple.finder", "com.apple.Safari", "us.zoom.xos", "com.tinyspeck.slackmacgap",
    "com.spotify.client", "com.figma.Desktop", "com.microsoft.VSCode", "com.matchbox.app"]) {
    assert.ok(!isSensitiveBundleID(id), id);
  }
  const health = "com.apple.Health";
  assert.equal(validateSubmission(submission({ bundleID: health, rows: [row({ app: health })] })).ok, false);
});
