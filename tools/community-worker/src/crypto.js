// Tokens and hashes. Uses the Web Crypto API, which both the Workers runtime and Node have, so `node --test` can import it.

const encoder = new TextEncoder();

function toHex(bytes) {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

function toBase64URL(bytes) {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** A random delete token: 32 bytes, base64url (43 characters). Only its hash is stored. */
export function generateToken() {
  return toBase64URL(crypto.getRandomValues(new Uint8Array(32)));
}

/** A random record ID: "s_" and 16 bytes in hex. Not derived from anything about the sender. */
export function generateID() {
  return "s_" + toHex(crypto.getRandomValues(new Uint8Array(16)));
}

/** SHA-256 of a string, as lowercase hex */
export async function sha256Hex(text) {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(String(text)));
  return toHex(new Uint8Array(digest));
}

/** Compares two strings without stopping at the first difference */
export function timingSafeEqual(a, b) {
  const x = encoder.encode(String(a));
  const y = encoder.encode(String(b));
  let diff = x.length ^ y.length;
  const length = Math.max(x.length, y.length);
  for (let i = 0; i < length; i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}
