import { test } from "node:test";
import assert from "node:assert/strict";
import { generateToken, generateID, sha256Hex, timingSafeEqual } from "../src/crypto.js";

test("SHA-256 matches known values", async () => {
  assert.equal(await sha256Hex(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
  assert.equal(await sha256Hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
});

test("tokens are random, URL-safe and 43 characters long", () => {
  const tokens = new Set(Array.from({ length: 200 }, generateToken));
  assert.equal(tokens.size, 200);
  for (const token of tokens) assert.match(token, /^[A-Za-z0-9_-]{43}$/);
});

test("IDs are random and have the expected form", () => {
  const ids = new Set(Array.from({ length: 200 }, generateID));
  assert.equal(ids.size, 200);
  for (const id of ids) assert.match(id, /^s_[0-9a-f]{32}$/);
});

test("timingSafeEqual", () => {
  assert.ok(timingSafeEqual("abc", "abc"));
  assert.ok(!timingSafeEqual("abc", "abd"));
  assert.ok(!timingSafeEqual("abc", "abcd"));
  assert.ok(!timingSafeEqual("", "a"));
});
