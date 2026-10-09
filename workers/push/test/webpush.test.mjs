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
import { forgetAccessToken, readServiceAccount, signedAssertion } from "../src/fcm.js";

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
  // 113: a followed vitrine's news opens the vitrine (its row names the
  // business, which the follower is not of), never anything but a slug.
  assert.equal(payloadFor({ kind: "vitrine_news", org_id: "o3", message: "m",
    params: { slug: "boutique-awa" } }, env).url,
    "https://dbms.kabore-boss.workers.dev/s/boutique-awa");
  assert.equal(payloadFor({ kind: "vitrine_news", org_id: "o3", message: "m",
    params: { slug: "../o/o3" } }, env).url,
    "https://dbms.kabore-boss.workers.dev/o/o3");
  assert.equal(payloadFor({ kind: "report_handled", message: "m", params: {} }, env).url,
    "https://dbms.kabore-boss.workers.dev/mon-compte/notifications");
  // 112: the platform's bell for an application opens its couriers, not
  // the board; the applicant's refusal or « new photo » their application.
  assert.equal(payloadFor({ kind: "courier_application", message: "m", params: { to: "platform" } }, env).url,
    "https://dbms.kabore-boss.workers.dev/console/livreurs");
  assert.equal(payloadFor({ kind: "courier_refused", message: "m" }, env).url,
    "https://dbms.kabore-boss.workers.dev/devenir-livreur");
  assert.equal(payloadFor({ kind: "courier_photo", message: "m" }, env).url,
    "https://dbms.kabore-boss.workers.dev/devenir-livreur");
  assert.equal(payloadFor({ kind: "courier_suspended", message: "m" }, env).url,
    "https://dbms.kabore-boss.workers.dev/livreur");
  // 111: an older app's request answered at once.
  assert.equal(payloadFor({ kind: "application_update_app", message: "m" }, env).url,
    "https://dbms.kabore-boss.workers.dev/creer-mon-activite");
});

test("the bell says Mara, whatever name the database's sentence was written in", () => {
  const p = payloadFor({ kind: "pro_active", org_id: "o1",
    message: "Kaj Pro est actif jusqu'au 10/03/2030. Kaj Consulting vous remercie." }, {});
  assert.equal(p.title, "Mara");
  assert.equal(p.body, "Mara Pro est actif jusqu'au 10/03/2030. Kaj Consulting vous remercie.");
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

// ------------------------------------------------------------------ 115

test("a customer's ring opens their own orders; the platform's its queue", () => {
  const env = { APP_ORIGIN: "https://app.example" };
  assert.equal(payloadFor({ kind: "order_accepted", org_id: "o1", message: "m",
    params: { to: "customer", booking: false } }, env).url, "https://app.example/mes-commandes");
  assert.equal(payloadFor({ kind: "order_accepted", org_id: "o1", message: "m",
    params: { to: "customer", booking: true } }, env).path, "/mon-compte/reservations");
  assert.equal(payloadFor({ kind: "order_in_transit", org_id: "o1", message: "m", scope: "customer" }, env).path,
    "/mes-commandes");
  assert.equal(payloadFor({ kind: "new_order", org_id: "o1", message: "m", params: { to: "shop" } }, env).path,
    "/o/o1/commandes");
  assert.equal(payloadFor({ kind: "org_application", message: "m" }, env).path, "/demandes");
  assert.equal(payloadFor({ kind: "spot_requested", message: "m" }, env).path, "/console/a-la-une");
  assert.equal(payloadFor({ kind: "new_device", message: "m" }, env).path, "/securite");
  assert.equal(payloadFor({ kind: "courier_received", message: "m", params: { to: "courier" } }, env).path,
    "/devenir-livreur");
  assert.equal(payloadFor({ kind: "delivery_available", org_id: "o1", message: "m", params: { to: "courier" } }, env).path,
    "/livreur");
  assert.equal(payloadFor({ kind: "test_push", message: "m", params: { to: "me" } }, env).path, "/");
});

async function serviceAccount() {
  const pair = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true, ["sign", "verify"]);
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  let s = "";
  for (const b of pkcs8) s += String.fromCharCode(b);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(s).replace(/(.{64})/g, "$1\n")}\n-----END PRIVATE KEY-----\n`;
  return {
    publicKey: pair.publicKey,
    json: JSON.stringify({ type: "service_account", project_id: "mara-test", client_email: "push@mara-test.iam.gserviceaccount.com",
      private_key: pem, token_uri: "https://oauth2.example/token" }),
  };
}

test("the FCM assertion is signed by the service account, for the messaging scope", async () => {
  const { publicKey, json } = await serviceAccount();
  const sa = readServiceAccount({ FCM_SERVICE_ACCOUNT: json });
  const jwt = await signedAssertion(sa, 1000);
  const [h, c, sig] = jwt.split(".");
  const claims = JSON.parse(td.decode(b64urlDecode(c)));
  assert.deepEqual(claims, { iss: "push@mara-test.iam.gserviceaccount.com",
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.example/token", iat: 1000, exp: 4600 });
  assert.equal(JSON.parse(td.decode(b64urlDecode(h))).alg, "RS256");
  assert.ok(await crypto.subtle.verify("RSASSA-PKCS1-v1_5", publicKey, b64urlDecode(sig), te.encode(`${h}.${c}`)));
  assert.equal(readServiceAccount({}), null);
  assert.equal(readServiceAccount({ FCM_SERVICE_ACCOUNT: "{not json" }), null);
});

test("deliver rings browsers and phones; phones stay dormant without the secret", async () => {
  forgetAccessToken();
  const { json } = await serviceAccount();
  const devices = [
    { endpoint: "https://p/alive", platform: "web", p256dh: "a", auth: "b", fcm_token: null },
    { endpoint: "fcm:tok-ok", platform: "android", p256dh: null, auth: null, fcm_token: "tok-ok" },
    { endpoint: "fcm:tok-gone", platform: "android", p256dh: null, auth: null, fcm_token: "tok-gone" },
  ];
  const calls = [];
  const fetchStub = async (url, init) => {
    calls.push({ url, init });
    if (url.endsWith("/push_devices")) return new Response(JSON.stringify(devices), { status: 200 });
    if (url === "https://oauth2.example/token") {
      return new Response(JSON.stringify({ access_token: "ya29.test", expires_in: 3600 }), { status: 200 });
    }
    if (url.startsWith("https://fcm.googleapis.com/v1/projects/mara-test/messages:send")) {
      const msg = JSON.parse(init.body).message;
      return msg.token === "tok-ok"
        ? new Response("{}", { status: 200 })
        : new Response(JSON.stringify({ error: { status: "NOT_FOUND", message: "UNREGISTERED" } }), { status: 404 });
    }
    return new Response("", { status: 204 });
  };
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const env = {
    SUPABASE_URL: "https://x.supabase.co", SUPABASE_SERVICE_ROLE_KEY: "service",
    VAPID_PUBLIC_KEY: b64urlEncode(await crypto.subtle.exportKey("raw", pair.publicKey)),
    VAPID_PRIVATE_KEY: JSON.stringify(await crypto.subtle.exportKey("jwk", pair.privateKey)),
    APP_ORIGIN: "https://app.example",
  };
  const row = { id: "n1", recipient_id: "u1", kind: "order_ready", org_id: "o1", message: "Prête",
    params: { to: "customer" } };

  // Without FCM_SERVICE_ACCOUNT: the browser only, the phones untouched.
  let result = await deliver(row, env, { sendPush: async () => 201, fetch: fetchStub });
  assert.deepEqual(result, { sent: 1, dropped: 0, failed: 0 });
  assert.ok(!calls.some((c) => c.url.includes("fcm.googleapis.com") || c.url.includes("oauth2")));

  calls.length = 0;
  result = await deliver(row, { ...env, FCM_SERVICE_ACCOUNT: json }, { sendPush: async () => 201, fetch: fetchStub });
  assert.deepEqual(result, { sent: 2, dropped: 1, failed: 0 });
  const sends = calls.filter((c) => c.url.includes("messages:send"));
  assert.equal(sends.length, 2);
  assert.ok(sends.every((c) => c.init.headers.Authorization === "Bearer ya29.test"));
  const sent = JSON.parse(sends[0].init.body).message;
  assert.deepEqual(sent.notification, { title: "Mara", body: "Prête" });
  assert.deepEqual(sent.data, { path: "/mes-commandes", url: "https://app.example/mes-commandes" });
  assert.equal(sent.android.notification.channel_id, "mara_alerts");
  // One token for both phones (cached), the gone one dropped by its endpoint.
  assert.equal(calls.filter((c) => c.url === "https://oauth2.example/token").length, 1);
  assert.deepEqual(calls.filter((c) => c.url.endsWith("/remove_push_target")).map((c) => JSON.parse(c.init.body)),
    [{ p_endpoint: "fcm:tok-gone" }]);
  // The key and the token never travel anywhere but Google.
  assert.ok(calls.filter((c) => c.url.startsWith("https://x.supabase.co")).every((c) => !c.init.body.includes("ya29")));
});

test("a token endpoint that fails is asked once per deliver, not once per phone", async () => {
  forgetAccessToken();
  const { json } = await serviceAccount();
  const devices = [1, 2, 3].map((i) => ({ endpoint: `fcm:tok-${i}`, platform: "android",
    p256dh: null, auth: null, fcm_token: `tok-${i}` }));
  const calls = [];
  const fetchStub = async (url, init) => {
    calls.push({ url, init });
    if (url.endsWith("/push_devices")) return new Response(JSON.stringify(devices), { status: 200 });
    if (url === "https://oauth2.example/token") return new Response("{}", { status: 500 });
    return new Response("{}", { status: 200 });
  };
  const env = { SUPABASE_URL: "https://x.supabase.co", SUPABASE_SERVICE_ROLE_KEY: "service",
    FCM_SERVICE_ACCOUNT: json };
  const row = { id: "n2", recipient_id: "u1", kind: "order_ready", org_id: "o1", message: "Prête",
    params: { to: "customer" } };
  let result = await deliver(row, env, { sendPush: async () => 201, fetch: fetchStub });
  assert.deepEqual(result, { sent: 0, dropped: 0, failed: 3 });
  assert.equal(calls.filter((c) => c.url === "https://oauth2.example/token").length, 1);
  assert.ok(!calls.some((c) => c.url.includes("messages:send")));
  assert.ok(!calls.some((c) => c.url.endsWith("/remove_push_target")));
  // The next deliver asks again (a failure is remembered for one call only).
  result = await deliver(row, env, { sendPush: async () => 201, fetch: fetchStub });
  assert.equal(calls.filter((c) => c.url === "https://oauth2.example/token").length, 2);
});
