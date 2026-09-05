// Web Push, by hand, on WebCrypto — because a Worker has no `web-push`
// package and the two RFCs involved are short enough to hold in one file.
//
//   RFC 8291  Message Encryption for Web Push (aes128gcm)
//   RFC 8292  VAPID: who is sending, signed
//
// What a browser's push service needs from us: a body encrypted to the
// browser's own P-256 key and auth secret (so the service that carries it
// cannot read it), and a JWT proving the sender is the site the browser
// subscribed to. Both are built here from primitives the platform has;
// nothing below is a hand-rolled cipher.
//
// Tested end to end in test/webpush.test.mjs, which plays the browser: it
// makes a subscription key pair, decrypts what `encrypt` produced, and
// verifies the VAPID signature with the public key.

const te = new TextEncoder();

// ---------------------------------------------------------------- base64url

export function b64urlEncode(bytes) {
  let s = "";
  for (const b of new Uint8Array(bytes)) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function b64urlDecode(text) {
  const padded = text.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - (text.length % 4)) % 4);
  const s = atob(padded);
  const out = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
  return out;
}

function concat(...parts) {
  const total = parts.reduce((n, p) => n + p.length, 0);
  const out = new Uint8Array(total);
  let at = 0;
  for (const p of parts) {
    out.set(p, at);
    at += p.length;
  }
  return out;
}

// HKDF-SHA256 extract-and-expand in one call, which is what WebCrypto's
// HKDF does: salt, then info, out to `length` bytes.
async function hkdf(salt, ikm, info, length) {
  const key = await crypto.subtle.importKey("raw", ikm, "HKDF", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits(
    { name: "HKDF", hash: "SHA-256", salt, info },
    key,
    length * 8,
  );
  return new Uint8Array(bits);
}

// ------------------------------------------------------------ RFC 8291

/// Encrypts `plaintext` (a Uint8Array) for the subscription whose public
/// key is `p256dh` and whose auth secret is `auth` (both base64url, as the
/// browser hands them out). Returns the aes128gcm body: header, then the
/// one record. Payloads here are a title and a line, far under one record.
export async function encrypt(plaintext, p256dh, auth) {
  const uaPublic = b64urlDecode(p256dh); // 65 bytes, uncompressed point
  const authSecret = b64urlDecode(auth); // 16 bytes
  if (uaPublic.length !== 65 || authSecret.length !== 16) {
    throw new Error("subscription keys have the wrong shape");
  }

  // Our ephemeral key pair, one per message.
  const local = await crypto.subtle.generateKey({ name: "ECDH", namedCurve: "P-256" }, true, ["deriveBits"]);
  const localPublic = new Uint8Array(await crypto.subtle.exportKey("raw", local.publicKey));
  const uaKey = await crypto.subtle.importKey("raw", uaPublic, { name: "ECDH", namedCurve: "P-256" }, false, []);
  const shared = new Uint8Array(await crypto.subtle.deriveBits({ name: "ECDH", public: uaKey }, local.privateKey, 256));

  // RFC 8291 §3.3: IKM from the shared secret, bound to both public keys.
  const keyInfo = concat(te.encode("WebPush: info\0"), uaPublic, localPublic);
  const ikm = await hkdf(authSecret, shared, keyInfo, 32);

  // RFC 8188: content encryption key and nonce from a fresh salt.
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const cek = await hkdf(salt, ikm, te.encode("Content-Encoding: aes128gcm\0"), 16);
  const nonce = await hkdf(salt, ikm, te.encode("Content-Encoding: nonce\0"), 12);

  // One record: the payload, then the 0x02 delimiter that marks it last.
  const record = concat(plaintext, new Uint8Array([2]));
  const aes = await crypto.subtle.importKey("raw", cek, "AES-GCM", false, ["encrypt"]);
  const ciphertext = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv: nonce }, aes, record));

  // Header: salt(16) | rs(4, big-endian) | idlen(1) | keyid(=our public key)
  const rs = new Uint8Array([0, 0, 0x10, 0]); // 4096
  const header = concat(salt, rs, new Uint8Array([localPublic.length]), localPublic);
  return concat(header, ciphertext);
}

// ------------------------------------------------------------ RFC 8292

/// Imports the VAPID private key. Accepts the JWK JSON `make-vapid.mjs`
/// prints, so the secret is one opaque string to store.
export async function importVapidPrivateKey(jwkJson) {
  const jwk = typeof jwkJson === "string" ? JSON.parse(jwkJson) : jwkJson;
  return crypto.subtle.importKey("jwk", jwk, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
}

/// The `Authorization: vapid t=<jwt>, k=<key>` value for a push service at
/// `endpoint`. The token names the service's origin as its audience, the
/// site's contact as its subject, and expires in twelve hours — long enough
/// to reuse across a burst, short enough that a leaked one is worthless.
export async function vapidAuthorization(endpoint, publicKeyB64url, privateKey, subject, now = Date.now()) {
  const aud = new URL(endpoint).origin;
  const header = b64urlEncode(te.encode(JSON.stringify({ typ: "JWT", alg: "ES256" })));
  const claims = b64urlEncode(te.encode(JSON.stringify({
    aud,
    exp: Math.floor(now / 1000) + 12 * 3600,
    sub: subject,
  })));
  const signingInput = `${header}.${claims}`;
  // WebCrypto's ECDSA signature is already the raw r||s form JWS wants.
  const sig = new Uint8Array(await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    privateKey,
    te.encode(signingInput),
  ));
  return `vapid t=${signingInput}.${b64urlEncode(sig)}, k=${publicKeyB64url}`;
}

/// Sends one encrypted payload to one subscription. Returns the push
/// service's status: 201 delivered, 404/410 gone (drop the subscription),
/// anything else a transient failure the caller may log and move on from.
export async function sendPush({ endpoint, p256dh, auth }, payload, vapid, { ttl = 3600, urgency = "high" } = {}) {
  const body = await encrypt(te.encode(JSON.stringify(payload)), p256dh, auth);
  const authorization = await vapidAuthorization(endpoint, vapid.publicKey, vapid.privateKey, vapid.subject);
  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      "Content-Type": "application/octet-stream",
      "Content-Encoding": "aes128gcm",
      "Content-Length": String(body.length),
      TTL: String(ttl),
      Urgency: urgency,
      Authorization: authorization,
    },
    body,
  });
  return response.status;
}
