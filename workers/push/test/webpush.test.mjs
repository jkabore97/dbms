// Plays the browser and the push service against workers/push.
//
//   node --test workers/push/test
//
// The browser: makes a subscription (a P-256 key pair and a 16-byte auth
// secret), receives what `encrypt` produced, and decrypts it the way RFC
// 8291 says a user agent does. If both sides agree on every derived key the
// payload comes back byte for byte; if any info string, salt or key order
// is wrong it comes back as an AES-GCM failure. The push service: verifies
// the VAPID JWT with the public key. The Worker: `deliver` counts a
// delivery, a dead endpoint (dropped through the RPC) and a failure.

import assert from "node:assert/strict";
import { test } from "node:test";

import {
  b64urlDecode,
  b64urlEncode,
  encrypt,
  importVapidPrivateKey,
  vapidAuthorization,
} from "../src/webpush.js";
import { deliver, payloadFor } from "../src/index.js";

const te = new TextEncoder();
const td = new TextDecoder();

async function hkdf(salt, ikm, info, length) {
  const key = await crypto.subtle.importKey("raw", ikm, "HKDF", false, ["deriveBits"]);
  return new Uint8Array(await crypto.subtle.deriveBits({ name: "HKDF", hash: "SHA-256", salt, info }, key, length * 8));
}

function concat(...parts) {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let at = 0;
  for (const p of parts) { out.set(p, at); at += p.length; }
  return out;
}

/// A browser subscription: what pushManager.subscribe() hands the page.
async function makeSubscription() {
  const ua = await crypto.subtle.generateKey({ name: "ECDH", namedCurve: "P-256" }, true, ["deriveBits"]);
  const p256dh = b64urlEncode(await crypto.subtle.exportKey("raw", ua.publicKey));
  const auth = b64urlEncode(crypto.getRandomValues(new Uint8Array(16)));
  return { ua, p256dh, auth, endpoint: "https://push.example.org/send/abc" };
}

/// RFC 8291 from the receiving side.
async function decrypt(body, sub) {
  const salt = body.slice(0, 16);
  const rs = new DataView(body.buffer, body.byteOffset + 16, 4).getUint32(0);
  const idlen = body[20];
  const localPublic = body.slice(21, 21 + idlen);
  const ciphertext = body.slice(21 + idlen);
  assert.equal(rs, 4096);
  assert.equal(idlen, 65);

  const uaPublic = b64urlDecode(sub.p256dh);
  const authSecret = b64urlDecode(sub.auth);
  const senderKey = await crypto.subtle.importKey("raw", localPublic, { name: "ECDH", namedCurve: "P-256" }, false, []);
  const shared = new Uint8Array(await crypto.subtle.deriveBits({ name: "ECDH", public: senderKey }, sub.ua.privateKey, 256));
  const ikm = await hkdf(authSecret, shared, concat(te.encode("WebPush: info\0"), uaPublic, localPublic), 32);
  const cek = await hkdf(salt, ikm, te.encode("Content-Encoding: aes128gcm\0"), 16);
  const nonce = await hkdf(salt, ikm, te.encode("Content-Encoding: nonce\0"), 12);
  const aes = await crypto.subtle.importKey("raw", cek, "AES-GCM", false, ["decrypt"]);
  const record = new Uint8Array(await crypto.subtle.decrypt({ name: "AES-GCM", iv: nonce }, aes, ciphertext));
  assert.equal(record[record.length - 1], 2, "last-record delimiter");
  return record.slice(0, -1);
}

test("base64url round-trips and drops padding", () => {
  const bytes = new Uint8Array([0, 1, 2, 250, 251, 252, 253, 254, 255]);
  const text = b64urlEncode(bytes);
  assert.doesNotMatch(text, /[+/=]/);
  assert.deepEqual(b64urlDecode(text), bytes);
});

test("what the Worker encrypts, the browser decrypts — byte for byte", async () => {
  const sub = await makeSubscription();
  const message = te.encode(JSON.stringify({ title: "Kaj", body: "Nouvelle commande — Boutique Awa" }));
  const body = await encrypt(message, sub.p256dh, sub.auth);
  assert.equal(td.decode(await decrypt(body, sub)), td.decode(message));
});

test("two encryptions of the same text differ (fresh key and salt each time)", async () => {
  const sub = await makeSubscription();
  const a = await encrypt(te.encode("x"), sub.p256dh, sub.auth);
  const b = await encrypt(te.encode("x"), sub.p256dh, sub.auth);
  assert.notDeepEqual(a, b);
});

test("malformed subscription keys are refused, not sent to", async () => {
  await assert.rejects(encrypt(te.encode("x"), b64urlEncode(new Uint8Array(10)), b64urlEncode(new Uint8Array(16))));
});

test("the VAPID header carries a JWT the push service can verify", async () => {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const jwk = await crypto.subtle.exportKey("jwk", pair.privateKey);
  const publicRaw = b64urlEncode(await crypto.subtle.exportKey("raw", pair.publicKey));
  const key = await importVapidPrivateKey(JSON.stringify(jwk));

  const header = await vapidAuthorization("https://push.example.org/send/abc", publicRaw, key, "mailto:kabore.boss@gmail.com", 1_000_000_000_000);
  const m = /^vapid t=([^,]+), k=(.+)$/.exec(header);
  assert.ok(m, header);
  assert.equal(m[2], publicRaw);

  const [h, c, s] = m[1].split(".");
  const claims = JSON.parse(td.decode(b64urlDecode(c)));
  assert.equal(claims.aud, "https://push.example.org");
  assert.equal(claims.sub, "mailto:kabore.boss@gmail.com");
  assert.equal(claims.exp, 1_000_000_000 + 12 * 3600);
  assert.deepEqual(JSON.parse(td.decode(b64urlDecode(h))), { typ: "JWT", alg: "ES256" });

  const ok = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" }, pair.publicKey, b64urlDecode(s), te.encode(`${h}.${c}`),
  );
  assert.equal(ok, true);
});

test("a tap lands where the bell points", () => {
  const env = { APP_ORIGIN: "https://dbms.kabore-boss.workers.dev/" };
  assert.equal(payloadFor({ kind: "order_placed", org_id: "o1", message: "m" }, env).url,
    "https://dbms.kabore-boss.workers.dev/o/o1/commandes");
  assert.equal(payloadFor({ kind: "courier_approved", message: "m" }, env).url,
    "https://dbms.kabore-boss.workers.dev/livreur");
  assert.equal(payloadFor({ kind: "low_stock", org_id: "o2", message: "m" }, env).url,
    "https://dbms.kabore-boss.workers.dev/o/o2");
  assert.equal(payloadFor({ kind: "org_application", message: "m", id: "n1" }, env).tag, "kaj-n1");
});

test("deliver counts what was sent, what was dead, and what failed", async () => {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const env = {
    SUPABASE_URL: "https://x.supabase.co",
    SUPABASE_SERVICE_ROLE_KEY: "service",
    VAPID_PUBLIC_KEY: b64urlEncode(await crypto.subtle.exportKey("raw", pair.publicKey)),
    VAPID_PRIVATE_KEY: JSON.stringify(await crypto.subtle.exportKey("jwk", pair.privateKey)),
    APP_ORIGIN: "https://app.example",
  };
  const rpcCalls = [];
  const fetchStub = async (url, init) => {
    rpcCalls.push({ url, body: JSON.parse(init.body), auth: init.headers.Authorization });
    if (url.endsWith("/push_targets")) {
      return new Response(JSON.stringify([
        { endpoint: "https://p/alive", p256dh: "a", auth: "b" },
        { endpoint: "https://p/dead", p256dh: "a", auth: "b" },
        { endpoint: "https://p/down", p256dh: "a", auth: "b" },
      ]), { status: 200 });
    }
    return new Response("", { status: 204 });
  };
  const statusFor = { "https://p/alive": 201, "https://p/dead": 410, "https://p/down": 500 };
  const sendStub = async (target) => statusFor[target.endpoint];

  const result = await deliver({ recipient_id: "u1", kind: "order_placed", org_id: "o1", message: "hi" }, env,
    { sendPush: sendStub, fetch: fetchStub });
  assert.deepEqual(result, { sent: 1, dropped: 1, failed: 1 });
  // The dead endpoint was dropped through the service-role RPC, and only it.
  const drops = rpcCalls.filter((c) => c.url.endsWith("/remove_push_target"));
  assert.deepEqual(drops.map((c) => c.body), [{ p_endpoint: "https://p/dead" }]);
  assert.ok(rpcCalls.every((c) => c.auth === "Bearer service"));
});

test("nobody subscribed means nothing sent and no key work", async () => {
  const env = { SUPABASE_URL: "https://x.supabase.co", SUPABASE_SERVICE_ROLE_KEY: "s" };
  const result = await deliver({ recipient_id: "u1" }, env,
    { sendPush: async () => 201, fetch: async () => new Response("[]", { status: 200 }) });
  assert.deepEqual(result, { sent: 0, dropped: 0, failed: 0 });
});
