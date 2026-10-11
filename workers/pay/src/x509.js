// Apple's signed payloads (JWS), verified against Apple's own certificate
// chain — on WebCrypto alone, with a small DER reader, so it runs the same
// in the Worker and in Node's tests.
//
// Everything Apple signs for a purchase — a transaction, a renewal, a
// server notification — is a compact JWS whose header carries `x5c`: the
// signing (leaf) certificate, Apple's intermediate (Worldwide Developer
// Relations), and Apple Root CA - G3. What is checked, as Apple's own
// App Store Server Library does:
//
//   1. alg is ES256 and the chain has exactly three certificates;
//   2. the last one IS Apple Root CA - G3: its DER's SHA-256 is pinned
//      below (never « a root that says it is Apple's »);
//   3. each certificate is signed by the next one's key, names it as its
//      issuer, and is within its dates; the intermediate is a CA;
//   4. the leaf carries Apple's receipt-signing mark (OID
//      1.2.840.113635.100.6.11.1) and the intermediate Apple's WWDR mark
//      (1.2.840.113635.100.6.2.1);
//   5. the JWS signature verifies with the leaf's key.
//
// The pin is a parameter only so a test can build its own chain; the
// Worker never passes one.
//
// Not done: an online revocation check (OCSP) of the leaf and the
// intermediate, which Apple's library makes when it can reach Apple.
// Accepted, with the root pinned: a payload is believed only when it came
// back from Apple's own API over TLS, which the Worker asked itself — a
// notification is only a wake-up (store.js appleNotify) — so a revoked
// signing key could only replay what Apple's API already said.

import { unb64, unb64url } from "./jwt.js";

/// SHA-256 of Apple Root CA - G3 (AppleRootCA-G3.cer), as Apple publishes
/// it at https://www.apple.com/certificateauthority/ and as Apple's and
/// the community's server libraries pin it.
export const APPLE_ROOT_G3_SHA256 =
  "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179";

const OID_LEAF = "1.2.840.113635.100.6.11.1";
const OID_INTERMEDIATE = "1.2.840.113635.100.6.2.1";
const OID_BASIC_CONSTRAINTS = "2.5.29.19";
const SIG_HASH = {
  "1.2.840.10045.4.3.2": "SHA-256",
  "1.2.840.10045.4.3.3": "SHA-384",
};
const CURVES = {
  "1.2.840.10045.3.1.7": { name: "P-256", size: 32 },
  "1.3.132.0.34": { name: "P-384", size: 48 },
};

export class SignatureError extends Error {}

// ------------------------------------------------------------
// DER
// ------------------------------------------------------------

function tlv(bytes, offset) {
  const tag = bytes[offset];
  let len = bytes[offset + 1];
  let head = 2;
  if (len & 0x80) {
    const n = len & 0x7f;
    if (n < 1 || n > 4) throw new SignatureError("DER length");
    len = 0;
    for (let i = 0; i < n; i++) len = (len * 256) + bytes[offset + 2 + i];
    head += n;
  }
  const start = offset + head;
  const end = start + len;
  if (end > bytes.length) throw new SignatureError("DER overrun");
  return { tag, start, end, offset, bytes };
}

function children(node) {
  const out = [];
  let at = node.start;
  while (at < node.end) {
    const child = tlv(node.bytes, at);
    out.push(child);
    at = child.end;
  }
  return out;
}

const raw = (node) => node.bytes.subarray(node.offset, node.end);
const content = (node) => node.bytes.subarray(node.start, node.end);

function oid(node) {
  const b = content(node);
  const parts = [Math.floor(b[0] / 40), b[0] % 40];
  let value = 0;
  for (let i = 1; i < b.length; i++) {
    value = (value * 128) + (b[i] & 0x7f);
    if (!(b[i] & 0x80)) {
      parts.push(value);
      value = 0;
    }
  }
  return parts.join(".");
}

function time(node) {
  const s = new TextDecoder().decode(content(node));
  const full = node.tag === 0x17 ? (Number(s.slice(0, 2)) < 50 ? "20" : "19") + s : s;
  return Date.UTC(Number(full.slice(0, 4)), Number(full.slice(4, 6)) - 1, Number(full.slice(6, 8)),
    Number(full.slice(8, 10)), Number(full.slice(10, 12)), Number(full.slice(12, 14)));
}

function same(a, b) {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

/// The parts of a certificate the chain check reads.
export function parseCertificate(der) {
  const cert = tlv(der, 0);
  const [tbs, sigAlg, sigValue] = children(cert);
  const fields = children(tbs);
  let i = 0;
  if (fields[0].tag === 0xa0) i++; // [0] version
  const issuer = fields[i + 2];
  const validity = children(fields[i + 3]);
  const subject = fields[i + 4];
  const spki = fields[i + 5];
  const extensions = [];
  let isCa = false;
  for (const f of fields.slice(i + 6)) {
    if (f.tag !== 0xa3) continue;
    for (const ext of children(children(f)[0])) {
      const parts = children(ext);
      const id = oid(parts[0]);
      extensions.push(id);
      if (id === OID_BASIC_CONSTRAINTS) {
        const value = parts[parts.length - 1];
        const seq = tlv(value.bytes, value.start);
        const inner = children(seq);
        isCa = inner.length > 0 && inner[0].tag === 0x01 && value.bytes[inner[0].start] !== 0;
      }
    }
  }
  const [alg] = children(spki);
  const algParts = children(alg);
  const curve = algParts[1] ? CURVES[oid(algParts[1])] : null;
  const sigBits = content(sigValue);
  return {
    der,
    tbs: raw(tbs),
    sigHash: SIG_HASH[oid(children(sigAlg)[0])] || null,
    signature: sigBits.subarray(1), // the BIT STRING's unused-bits byte
    issuer: raw(issuer),
    subject: raw(subject),
    notBefore: time(validity[0]),
    notAfter: time(validity[1]),
    spki: raw(spki),
    curve,
    extensions,
    isCa,
  };
}

/// An X.509 ECDSA signature (DER SEQUENCE of r, s) as WebCrypto's r‖s.
function derToRaw(sig, size) {
  const seq = tlv(sig, 0);
  const [r, s] = children(seq).map((n) => {
    let v = content(n);
    while (v.length > size && v[0] === 0) v = v.subarray(1);
    if (v.length > size) throw new SignatureError("signature size");
    const padded = new Uint8Array(size);
    padded.set(v, size - v.length);
    return padded;
  });
  const out = new Uint8Array(size * 2);
  out.set(r, 0);
  out.set(s, size);
  return out;
}

async function keyOf(cert) {
  if (!cert.curve) throw new SignatureError("not an EC key");
  return crypto.subtle.importKey("spki", cert.spki,
    { name: "ECDSA", namedCurve: cert.curve.name }, false, ["verify"]);
}

async function sha256Hex(bytes) {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  return [...digest].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/// Checks Apple's x5c chain (base64 DER, leaf first) and answers the leaf.
export async function verifyAppleChain(x5c, { rootSha256 = APPLE_ROOT_G3_SHA256, now = Date.now() } = {}) {
  if (!Array.isArray(x5c) || x5c.length !== 3) throw new SignatureError("x5c must hold three certificates");
  const certs = x5c.map((c) => parseCertificate(unb64(c)));
  const [leaf, intermediate, root] = certs;
  if ((await sha256Hex(root.der)) !== String(rootSha256).toLowerCase().replace(/[^0-9a-f]/g, "")) {
    throw new SignatureError("not Apple's root");
  }
  for (const c of certs) {
    if (!(c.notBefore <= now && now <= c.notAfter)) throw new SignatureError("certificate out of date");
  }
  for (let i = 0; i < 2; i++) {
    const subject = certs[i];
    const issuer = certs[i + 1];
    if (!same(subject.issuer, issuer.subject)) throw new SignatureError("broken chain");
    if (!issuer.isCa) throw new SignatureError("issuer is not a CA");
    if (!subject.sigHash) throw new SignatureError("unknown signature algorithm");
    const ok = await crypto.subtle.verify({ name: "ECDSA", hash: subject.sigHash },
      await keyOf(issuer), derToRaw(subject.signature, issuer.curve.size), subject.tbs);
    if (!ok) throw new SignatureError("bad certificate signature");
  }
  if (!leaf.extensions.includes(OID_LEAF)) throw new SignatureError("not Apple's signing certificate");
  if (!intermediate.extensions.includes(OID_INTERMEDIATE)) throw new SignatureError("not Apple's intermediate");
  return leaf;
}

/// A compact JWS signed by the App Store: its payload, or SignatureError.
export async function verifyAppleJws(jws, options = {}) {
  const parts = String(jws || "").split(".");
  if (parts.length !== 3) throw new SignatureError("not a JWS");
  let header;
  try {
    header = JSON.parse(new TextDecoder().decode(unb64url(parts[0])));
  } catch {
    throw new SignatureError("bad JWS header");
  }
  if (header.alg !== "ES256") throw new SignatureError("not ES256");
  const leaf = await verifyAppleChain(header.x5c, options);
  if (leaf.curve?.name !== "P-256") throw new SignatureError("ES256 needs a P-256 key");
  const ok = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, await keyOf(leaf),
    unb64url(parts[2]), new TextEncoder().encode(`${parts[0]}.${parts[1]}`));
  if (!ok) throw new SignatureError("bad JWS signature");
  try {
    return JSON.parse(new TextDecoder().decode(unb64url(parts[1])));
  } catch {
    throw new SignatureError("bad JWS payload");
  }
}
