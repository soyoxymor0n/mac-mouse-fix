// Mac Mouse Fix NG community setups: the submission Worker.
//
// POST /submit  body: a setup in the repository format. Stored with status "pending" for review. Answers 201 with
//               { id, deleteToken, status, license }. The token is returned only here; the database keeps its SHA-256 hash.
// POST /delete  body: { id, token }. Answers 204, or 404 if the ID and token don't match (it doesn't say which part was wrong).
// Anything else answers 404 (unknown path) or 405 (wrong method).
//
// Privacy: no IP address, no headers and no other data about the sender are read or stored. The Worker writes no logs of its own.
// Nothing is public until the owner copies a reviewed record into the setups repository.

import { validateSubmission, MAX_BYTES, LICENSE } from "./validate.js";
import { generateID, generateToken, sha256Hex, timingSafeEqual } from "./crypto.js";

const ID_PATTERN = /^s_[0-9a-f]{32}$/;
const MAX_TOKEN_LENGTH = 128;

export default {
  async fetch(request, env) {
    return handle(request, env);
  },
};

/** The whole Worker as one function, so tests can call it with a fake database */
export async function handle(request, env, now = () => new Date()) {
  const path = new URL(request.url).pathname;
  const routes = { "/submit": submit, "/delete": remove };
  const route = routes[path];
  if (!route) return json(404, { error: "not found" });
  if (request.method !== "POST") return json(405, { error: "method not allowed" }, { Allow: "POST" });
  try {
    return await route(request, env, now);
  } catch {
    // No details: an error message could hold parts of the request
    return json(500, { error: "server error" });
  }
}

async function submit(request, env, now) {
  const body = await readJSON(request);
  if (body.error) return body.error;

  const result = validateSubmission(body.value);
  if (!result.ok) return json(422, { error: "invalid submission", details: result.errors });

  const id = generateID();
  const token = generateToken();
  const tokenHash = await sha256Hex(token);
  const submission = result.submission;

  await env.DB.prepare(
    "INSERT INTO submissions (id, status, bundle_id, title, submission, delete_token_hash, created_at, license) VALUES (?1, 'pending', ?2, ?3, ?4, ?5, ?6, ?7)"
  )
    .bind(id, submission.bundleID, submission.title, JSON.stringify(submission), tokenHash, now().toISOString(), LICENSE)
    .run();

  return json(201, { id, deleteToken: token, status: "pending", license: LICENSE });
}

async function remove(request, env) {
  const body = await readJSON(request);
  if (body.error) return body.error;

  const notFound = json(404, { error: "not found" });
  const { id, token } = body.value ?? {};
  if (typeof id !== "string" || !ID_PATTERN.test(id)) return notFound;
  if (typeof token !== "string" || token.length === 0 || token.length > MAX_TOKEN_LENGTH) return notFound;

  const record = await env.DB.prepare("SELECT delete_token_hash, status FROM submissions WHERE id = ?1").bind(id).first();
  const tokenHash = await sha256Hex(token);
  if (!record || !timingSafeEqual(record.delete_token_hash, tokenHash)) return notFound;

  if (record.status === "published") {
    // The setup is in the public repository. Keep a marker, so the owner knows to remove it there, then deletes the row.
    await env.DB.prepare("UPDATE submissions SET status = 'delete_requested', submission = '{}' WHERE id = ?1").bind(id).run();
  } else {
    await env.DB.prepare("DELETE FROM submissions WHERE id = ?1").bind(id).run();
  }
  return new Response(null, { status: 204, headers: { "Cache-Control": "no-store" } });
}

/** Reads at most MAX_BYTES and parses them as JSON. Returns { value } or { error: Response }. */
async function readJSON(request) {
  const declared = Number(request.headers.get("Content-Length"));
  if (Number.isFinite(declared) && declared > MAX_BYTES) return { error: json(413, { error: "body larger than 16 KB" }) };
  const contentType = request.headers.get("Content-Type") ?? "";
  if (!contentType.toLowerCase().startsWith("application/json")) return { error: json(415, { error: "expected application/json" }) };

  const bytes = await readCapped(request, MAX_BYTES);
  if (bytes === null) return { error: json(413, { error: "body larger than 16 KB" }) };
  try {
    return { value: JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)) };
  } catch {
    return { error: json(400, { error: "body is not JSON" }) };
  }
}

/** The body, or null as soon as it is longer than `max` */
async function readCapped(request, max) {
  if (!request.body) return new Uint8Array();
  const reader = request.body.getReader();
  const chunks = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > max) {
      await reader.cancel();
      return null;
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}

function json(status, object, headers = {}) {
  return new Response(JSON.stringify(object), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", ...headers },
  });
}
