// The app and the Worker must refuse the same apps and key combinations. This reads the Swift sources as text.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { SENSITIVE_BUNDLE_ID_PREFIXES, SENSITIVE_KEYWORDS, DENYLIST, TITLES } from "../src/validate.js";

const appTabs = fileURLToPath(new URL("../../../App/UI/Main/Tabs/ButtonTab/AppTabs/", import.meta.url));
const sharing = readFileSync(appTabs + "CommunitySharing.swift", "utf8");
const setups = readFileSync(appTabs + "CommunitySetups.swift", "utf8");

function swiftStringArray(source, name) {
  const match = source.match(new RegExp(`static let ${name}: \\[String\\] = \\[([^\\]]*)\\]`));
  assert.ok(match, `${name} not found in the Swift source`);
  return [...match[1].matchAll(/"([^"]*)"/g)].map((m) => m[1]);
}

test("sensitive bundle ID prefixes are the same in the app", () => {
  assert.deepEqual(swiftStringArray(sharing, "bundleIDPrefixes"), SENSITIVE_BUNDLE_ID_PREFIXES);
});

test("sensitive keywords are the same in the app", () => {
  assert.deepEqual(swiftStringArray(sharing, "keywords"), SENSITIVE_KEYWORDS);
});

test("titles are the same in the app", () => {
  assert.deepEqual(swiftStringArray(sharing, "titles"), TITLES);
});

test("the key denylist is the same in the app", () => {
  const match = setups.match(/static let denylist: \[\(keycode: Int, flags: Int\)\] = \[([^\n]*)\]/);
  assert.ok(match);
  const pairs = [...match[1].matchAll(/\((\d+),\s*(0x[0-9A-Fa-f]+|\d+)\)/g)].map((m) => ({ keycode: Number(m[1]), flags: Number(m[2]) }));
  assert.deepEqual(pairs, DENYLIST);
});
