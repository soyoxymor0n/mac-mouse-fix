// The Worker's routes against an in-memory stand-in for D1. No network.
import { test } from "node:test";
import assert from "node:assert/strict";
import { handle } from "../src/index.js";
import { sha256Hex } from "../src/crypto.js";

/** Understands exactly the statements src/index.js uses */
class FakeD1 {
  constructor() {
    this.rows = new Map();
  }
  prepare(sql) {
    const db = this;
    return {
      bind(...args) {
        return {
          async run() {
            if (sql.startsWith("INSERT INTO submissions")) {
              const [id, bundle_id, title, submission, delete_token_hash, created_at, license] = args;
              db.rows.set(id, { id, status: "pending", bundle_id, title, submission, delete_token_hash, created_at, license });
            } else if (sql.startsWith("DELETE FROM submissions")) {
              db.rows.delete(args[0]);
            } else if (sql.startsWith("UPDATE submissions")) {
              const row = db.rows.get(args[0]);
              row.status = "delete_requested";
              row.submission = "{}";
            } else {
              throw new Error("unexpected SQL: " + sql);
            }
            return { success: true };
          },
          async first() {
            if (!sql.startsWith("SELECT")) throw new Error("unexpected SQL: " + sql);
            const row = db.rows.get(args[0]);
            return row ? { delete_token_hash: row.delete_token_hash, status: row.status } : null;
          },
        };
      },
    };
  }
}

const base = "https://worker.test";
const chrome = "com.google.Chrome";
const setup = {
  schemaVersion: 1,
  bundleID: chrome,
  title: "Tab switching",
  rows: [{ trigger: { button: 4, duration: "click", level: 1 }, modifiers: {}, effect: { type: "keyboardShortcut", keycode: 13, flags: 1048576 }, app: chrome }],
};

function post(path, body, headers = { "Content-Type": "application/json" }) {
  return new Request(base + path, { method: "POST", headers: { "CF-Connecting-IP": "203.0.113.7", ...headers }, body: typeof body === "string" ? body : JSON.stringify(body) });
}

const fixedNow = () => new Date("2026-10-29T12:00:00Z");

test("submit stores a pending record with the token hash and the license, and no IP", async () => {
  const env = { DB: new FakeD1() };
  const response = await handle(post("/submit", setup), env, fixedNow);
  assert.equal(response.status, 201);
  const answer = await response.json();
  assert.match(answer.id, /^s_[0-9a-f]{32}$/);
  assert.equal(answer.status, "pending");
  assert.equal(answer.license, "CC0-1.0");

  const row = env.DB.rows.get(answer.id);
  assert.equal(row.status, "pending");
  assert.equal(row.license, "CC0-1.0");
  assert.equal(row.created_at, "2026-10-29T12:00:00.000Z");
  assert.equal(row.delete_token_hash, await sha256Hex(answer.deleteToken));
  assert.ok(!JSON.stringify(row).includes(answer.deleteToken), "the token itself is not stored");
  assert.ok(!JSON.stringify(row).includes("203.0.113.7"), "the IP address is not stored");
  assert.deepEqual(JSON.parse(row.submission), setup);
});

test("submit refuses invalid, oversized, non-JSON and denylisted bodies", async () => {
  const env = { DB: new FakeD1() };
  assert.equal((await handle(post("/submit", { ...setup, title: "Free text" }), env)).status, 422);
  const quit = { ...setup, rows: [{ ...setup.rows[0], effect: { type: "keyboardShortcut", keycode: 12, flags: 0x100000 } }] };
  assert.equal((await handle(post("/submit", quit), env)).status, 422);
  assert.equal((await handle(post("/submit", "{not json"), env)).status, 400);
  assert.equal((await handle(post("/submit", "x".repeat(16 * 1024 + 1)), env)).status, 413);
  assert.equal((await handle(post("/submit", setup, { "Content-Type": "text/plain" }), env)).status, 415);
  assert.equal(env.DB.rows.size, 0, "nothing was stored");
});

test("delete with the right token removes the record", async () => {
  const env = { DB: new FakeD1() };
  const { id, deleteToken } = await (await handle(post("/submit", setup), env)).json();
  const response = await handle(post("/delete", { id, token: deleteToken }), env);
  assert.equal(response.status, 204);
  assert.equal(env.DB.rows.size, 0);
});

test("delete answers 404 for a wrong token, an unknown ID or a malformed body, without saying which", async () => {
  const env = { DB: new FakeD1() };
  const { id, deleteToken } = await (await handle(post("/submit", setup), env)).json();
  const wrongToken = await handle(post("/delete", { id, token: deleteToken + "x" }), env);
  const unknownID = await handle(post("/delete", { id: "s_" + "0".repeat(32), token: deleteToken }), env);
  const missing = await handle(post("/delete", {}), env);
  for (const response of [wrongToken, unknownID, missing]) {
    assert.equal(response.status, 404);
    assert.deepEqual(await response.json(), { error: "not found" });
  }
  assert.equal(env.DB.rows.size, 1, "the record is still there");
});

test("delete of a published record leaves a marker for the owner", async () => {
  const env = { DB: new FakeD1() };
  const { id, deleteToken } = await (await handle(post("/submit", setup), env)).json();
  env.DB.rows.get(id).status = "published";
  assert.equal((await handle(post("/delete", { id, token: deleteToken }), env)).status, 204);
  assert.equal(env.DB.rows.get(id).status, "delete_requested");
  assert.equal(env.DB.rows.get(id).submission, "{}");
});

test("other methods and paths are refused", async () => {
  const env = { DB: new FakeD1() };
  assert.equal((await handle(new Request(base + "/submit"), env)).status, 405);
  assert.equal((await handle(new Request(base + "/delete", { method: "PUT", body: "{}" }), env)).status, 405);
  assert.equal((await handle(new Request(base + "/"), env)).status, 404);
  assert.equal((await handle(post("/list", {}), env)).status, 404);
  assert.equal((await handle(new Request(base + "/submissions", { method: "GET" }), env)).status, 404);
});
