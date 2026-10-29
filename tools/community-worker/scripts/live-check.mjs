#!/usr/bin/env node
// Checks a running community Worker end to end: reachability, validation, size limit, delete.
// Works against the deployed Worker, or against `wrangler dev` on this machine.
//
//   node scripts/live-check.mjs https://<worker-url>
//   node scripts/live-check.mjs http://localhost:8787
//
// Prints one line per check with the HTTP status. It never prints a delete token.
// Exit code 0 when every check matches, 1 otherwise.

const base = (process.argv[2] ?? "").replace(/\/+$/, "");
if (!base) {
  console.error("usage: node scripts/live-check.mjs <base-url>");
  process.exit(2);
}

const validSetup = {
  schemaVersion: 1,
  bundleID: "com.example.mmftest",
  title: "Other",
  rows: [
    {
      app: "com.example.mmftest",
      effect: { flags: 1048576, keycode: 45, type: "keyboardShortcut" },
      modifiers: {},
      trigger: { button: 4, duration: "click", level: 1 },
    },
  ],
};

async function call(method, path, { body, contentType = "application/json" } = {}) {
  const headers = {};
  if (contentType) headers["Content-Type"] = contentType;
  const response = await fetch(base + path, {
    method,
    headers,
    body,
    signal: AbortSignal.timeout(20000),
  });
  const text = await response.text();
  let json = null;
  try {
    json = JSON.parse(text);
  } catch {
    // not JSON, which is fine for error answers
  }
  return { status: response.status, json };
}

let failures = 0;
function report(name, got, expected) {
  const ok = got === expected;
  if (!ok) failures += 1;
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}: got ${got}, expected ${expected}`);
}

// 1. Reachability: a GET to /submit is refused on purpose.
try {
  report("GET /submit refused", (await call("GET", "/submit", { contentType: null })).status, 405);
} catch (error) {
  console.log(`FAIL  reachability: ${error.cause?.code ?? error.message}`);
  process.exit(1);
}

// 2. A valid setup is stored and answers 201 with an ID and a delete token.
let created = null;
try {
  created = await call("POST", "/submit", { body: JSON.stringify(validSetup) });
  report("POST /submit valid setup", created.status, 201);
  const hasFields = Boolean(created.json?.id) && Boolean(created.json?.deleteToken);
  if (!hasFields) failures += 1;
  console.log(`${hasFields ? "PASS" : "FAIL"}  reply has id and deleteToken`);
} catch (error) {
  failures += 1;
  console.log(`FAIL  POST /submit valid setup: ${error.message}`);
}

// 3. Validation and transport rules.
report("POST /submit unknown title", (await call("POST", "/submit", { body: JSON.stringify({ ...validSetup, title: "Nope" }) })).status, 422);
report("POST /submit body is not JSON", (await call("POST", "/submit", { body: "{not json" })).status, 400);
report("POST /submit wrong content type", (await call("POST", "/submit", { body: JSON.stringify(validSetup), contentType: "text/plain" })).status, 415);
const padded = JSON.stringify({ ...validSetup, pad: "x".repeat(17 * 1024) });
report("POST /submit larger than 16 KB", (await call("POST", "/submit", { body: padded })).status, 413);
report("POST /unknown path", (await call("POST", "/unknown", { body: "{}" })).status, 404);

// 4. Delete: a wrong token is refused, the right token deletes, and a second delete is refused.
if (created?.json?.id && created?.json?.deleteToken) {
  const { id, deleteToken } = created.json;
  report("POST /delete wrong token", (await call("POST", "/delete", { body: JSON.stringify({ id, token: "wrong-token" }) })).status, 404);
  report("POST /delete right token", (await call("POST", "/delete", { body: JSON.stringify({ id, token: deleteToken }) })).status, 204);
  report("POST /delete the same record again", (await call("POST", "/delete", { body: JSON.stringify({ id, token: deleteToken }) })).status, 404);
} else {
  console.log("SKIP  delete checks: no record was created");
}

console.log(failures === 0 ? "ALL CHECKS PASSED" : `${failures} CHECK(S) FAILED`);
process.exit(failures === 0 ? 0 : 1);
