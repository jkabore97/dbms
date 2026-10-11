// The few pieces of JOSE the store doors need, on WebCrypto alone (the
// same API in a Cloudflare Worker and in Node's tests), no library:
//
//   * an ES256 JWT, signed with an Apple .p8 key: the App Store Server
//     API's bearer token (In-App Purchase key, 130) and Sign in with
//     Apple's client secret (account deletion, workers/account-admin);
//   * an RS256 JWT, signed with a Google service account's key: traded for
//     an access token to the Google Play Developer API;
//   * base64url both ways, and a PEM's bytes.
//
// workers/account-admin imports this file too (its revocation of a Sign in
// with Apple token); wrangler bundles it into each Worker.

const enc = new TextEncoder();

export function b64url(bytes) {
  const data = typeof bytes === "string" ? enc.encode(bytes) : new Uint8Array(bytes);
  let bin = "";
  for (let i = 0; i < data.length; i++) bin += String.fromCharCode(data[i]);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function unb64url(text) {
  const s = String(text).replace(/-/g, "+").replace(/_/g, "/");
  const pad = s.length % 4 === 0 ? "" : "=".repeat(4 - (s.length % 4));
  const bin = atob(s + pad);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export function unb64(text) {
  const bin = atob(String(text).replace(/\s+/g, ""));
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

/// The DER inside a PEM (« -----BEGIN PRIVATE KEY----- … »). A key pasted
/// into a GitHub secret often keeps literal « \n »: they are undone.
export function pemToDer(pem) {
  const body = String(pem || "")
    .replace(/\\n/g, "\n")
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s+/g, "");
  if (!body) throw new Error("empty key");
  return unb64(body);
}

export function decodeJwtPart(part) {
  return JSON.parse(new TextDecoder().decode(unb64url(part)));
}

/// A JWT signed ES256 with an Apple .p8 (PKCS#8, P-256) key.
export async function signEs256(header, claims, pkcs8Pem) {
  const key = await crypto.subtle.importKey(
    "pkcs8", pemToDer(pkcs8Pem), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const input = `${b64url(JSON.stringify({ alg: "ES256", ...header }))}.${b64url(JSON.stringify(claims))}`;
  // WebCrypto's ECDSA signature is already JOSE's r‖s.
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, enc.encode(input));
  return `${input}.${b64url(sig)}`;
}

/// A JWT signed RS256 with a service account's PKCS#8 RSA key.
export async function signRs256(header, claims, pkcs8Pem) {
  const key = await crypto.subtle.importKey(
    "pkcs8", pemToDer(pkcs8Pem), { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const input = `${b64url(JSON.stringify({ alg: "RS256", typ: "JWT", ...header }))}.${b64url(JSON.stringify(claims))}`;
  const sig = await crypto.subtle.sign({ name: "RSASSA-PKCS1-v1_5" }, key, enc.encode(input));
  return `${input}.${b64url(sig)}`;
}

/// Constant-time comparison of two strings (a shared secret in a URL).
export function sameSecret(a, b) {
  const x = enc.encode(String(a ?? ""));
  const y = enc.encode(String(b ?? ""));
  let diff = x.length ^ y.length;
  const n = Math.max(x.length, y.length);
  for (let i = 0; i < n; i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0 && x.length > 0;
}
