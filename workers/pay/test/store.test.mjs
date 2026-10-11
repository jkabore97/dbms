// Plays Apple, Google and the database against workers/pay's store doors
// (130): /store/verify, /store/apple-notify, /store/google-notify and the
// daily re-check.
//
//   node --test workers/pay/test
//
// Apple's JWS are signed here by a chain this file builds — a root, an
// intermediate and a leaf, with Apple's two marks — so the verifier runs
// for real; the root's pin is the test's own (io.verify.rootSha256).
// Nothing secret is committed: every key is generated when the test runs.

import assert from "node:assert/strict";
import { createHash, generateKeyPairSync, sign as nodeSign } from "node:crypto";
import { test } from "node:test";

import { storeDoor } from "../src/index.js";
import { APPLE_ROOT_G3_SHA256, SignatureError, verifyAppleJws } from "../src/x509.js";
import { appleState } from "../src/apple.js";
import { googleState } from "../src/google.js";
import { storeRecheck } from "../src/store.js";
import { decodeJwtPart } from "../src/jwt.js";

const ORG = "52000000-0000-0000-0000-0000000000a1";
const OTHER = "52000000-0000-0000-0000-0000000000b2";
const OWNER = "51000000-0000-0000-0000-000000000001";

// ------------------------------------------------------------
// A certificate chain, built with a few lines of DER
// ------------------------------------------------------------

function der(tag, ...parts) {
  const body = Buffer.concat(parts.map((p) => Buffer.from(p)));
  let len;
  if (body.length < 128) len = Buffer.from([body.length]);
  else if (body.length < 256) len = Buffer.from([0x81, body.length]);
  else len = Buffer.from([0x82, body.length >> 8, body.length & 0xff]);
  return Buffer.concat([Buffer.from([tag]), len, body]);
}
const seq = (...p) => der(0x30, ...p);
const set = (...p) => der(0x31, ...p);
function oid(dotted) {
  const [a, b, ...rest] = dotted.split(".").map(Number);
  const bytes = [a * 40 + b];
  for (const n of rest) {
    const chunk = [];
    let v = n;
    do { chunk.unshift(v & 0x7f); v = Math.floor(v / 128); } while (v > 0);
    for (let i = 0; i < chunk.length - 1; i++) chunk[i] |= 0x80;
    bytes.push(...chunk);
  }
  return der(0x06, Buffer.from(bytes));
}
const utf8 = (s) => der(0x0c, Buffer.from(s));
const name = (cn) => seq(set(seq(oid("2.5.4.3"), utf8(cn))));
const utc = (d) => der(0x17, Buffer.from(d.toISOString().replace(/[-:T]/g, "").slice(2, 14) + "Z"));
const int = (n) => der(0x02, Buffer.from([n]));

function makeCert({ cn, issuerCn, key, issuerKey, hash, ca, marks = [], notAfter }) {
  const spki = key.publicKey.export({ type: "spki", format: "der" });
  const sigOid = hash === "sha384" ? "1.2.840.10045.4.3.3" : "1.2.840.10045.4.3.2";
  const exts = [
    seq(oid("2.5.29.19"), der(0x01, Buffer.from([0xff])), der(0x04, ca ? seq(der(0x01, Buffer.from([0xff]))) : seq())),
    ...marks.map((m) => seq(oid(m), der(0x04, Buffer.from([0x05, 0x00])))),
  ];
  const tbs = seq(
    der(0xa0, int(2)),
    int(Math.floor(Math.random() * 100) + 1),
    seq(oid(sigOid)),
    name(issuerCn),
    seq(utc(new Date(Date.now() - 86_400_000)), utc(notAfter || new Date(Date.now() + 365 * 86_400_000))),
    name(cn),
    spki,
    der(0xa3, seq(...exts)),
  );
  const signature = nodeSign(hash, tbs, { key: issuerKey.privateKey, dsaEncoding: "der" });
  return seq(tbs, seq(oid(sigOid)), der(0x03, Buffer.concat([Buffer.from([0]), signature])));
}

function chain({ leafMark = true, interMark = true, leafNotAfter } = {}) {
  const rootKey = generateKeyPairSync("ec", { namedCurve: "P-384" });
  const interKey = generateKeyPairSync("ec", { namedCurve: "P-384" });
  const leafKey = generateKeyPairSync("ec", { namedCurve: "P-256" });
  const root = makeCert({ cn: "Test Root G3", issuerCn: "Test Root G3", key: rootKey, issuerKey: rootKey, hash: "sha384", ca: true });
  const inter = makeCert({ cn: "Test WWDR G6", issuerCn: "Test Root G3", key: interKey, issuerKey: rootKey, hash: "sha384", ca: true,
    marks: interMark ? ["1.2.840.113635.100.6.2.1"] : [] });
  const leaf = makeCert({ cn: "Test Prod ECC Mac App Store", issuerCn: "Test WWDR G6", key: leafKey, issuerKey: interKey, hash: "sha256", ca: false,
    marks: leafMark ? ["1.2.840.113635.100.6.11.1"] : [], notAfter: leafNotAfter });
  return {
    x5c: [leaf, inter, root].map((c) => c.toString("base64")),
    leafKey,
    rootSha256: createHash("sha256").update(root).digest("hex"),
  };
}

const CHAIN = chain();
const VERIFY = { rootSha256: CHAIN.rootSha256 };

const b64u = (b) => Buffer.from(b).toString("base64url");
function jws(payload, c = CHAIN) {
  const head = b64u(JSON.stringify({ alg: "ES256", x5c: c.x5c }));
  const body = b64u(JSON.stringify(payload));
  const sig = nodeSign("sha256", Buffer.from(`${head}.${body}`), { key: c.leafKey.privateKey, dsaEncoding: "ieee-p1363" });
  return `${head}.${body}.${b64u(sig)}`;
}

// ------------------------------------------------------------
// The world: Apple, Google and PostgREST, faked
// ------------------------------------------------------------

const iapKey = generateKeyPairSync("ec", { namedCurve: "P-256" });
const playKey = generateKeyPairSync("rsa", { modulusLength: 2048 });
const env = {
  SUPABASE_URL: "https://db.example",
  SUPABASE_PUBLISHABLE_KEY: "pub",
  SUPABASE_SERVICE_ROLE_KEY: "service",
  APPLE_IAP_KEY_ID: "KEY123",
  APPLE_IAP_ISSUER_ID: "issuer-uuid",
  APPLE_IAP_PRIVATE_KEY: iapKey.privateKey.export({ type: "pkcs8", format: "pem" }),
  APPLE_BUNDLE_ID: "bf.kaj.app",
  PLAY_SERVICE_ACCOUNT_JSON: JSON.stringify({
    client_email: "mara@play.iam.gserviceaccount.com",
    private_key: playKey.privateKey.export({ type: "pkcs8", format: "pem" }),
    token_uri: "https://oauth2.example/token",
  }),
  GOOGLE_NOTIFY_SECRET: "s3cret-pubsub",
};

const DAY = 86_400_000;
const tx = (over = {}) => ({
  transactionId: "2000000111",
  originalTransactionId: "2000000100",
  bundleId: "bf.kaj.app",
  productId: "bf.kaj.app.pro.monthly",
  expiresDate: Date.now() + 20 * DAY,
  appAccountToken: ORG,
  environment: "Sandbox",
  type: "Auto-Renewable Subscription",
  ...over,
});

const sub = (over = {}) => ({
  subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
  acknowledgementState: "ACKNOWLEDGEMENT_STATE_PENDING",
  externalAccountIdentifiers: { obfuscatedExternalAccountId: ORG },
  lineItems: [{
    productId: "mara_pro",
    expiryTime: new Date(Date.now() + 30 * DAY).toISOString(),
    autoRenewingPlan: { autoRenewEnabled: true },
    offerDetails: { basePlanId: "monthly" },
  }],
  ...over,
});

/// A fake world. `db` is the store_subscriptions table as store_settle
/// keeps it (by platform + original id, one business each).
function world({ apple = {}, google = {}, admin = true, sandboxOk = true, gone = [] } = {}) {
  const calls = [];
  const db = new Map();
  const fetchImpl = async (url, init = {}) => {
    calls.push({ url, method: init.method, headers: init.headers, body: init.body });
    if (url.startsWith("https://api.storekit")) {
      const sandbox = url.includes("sandbox");
      const m = url.match(/\/inApps\/v1\/(transactions|subscriptions)\/(\d+)/);
      const known = apple[m[2]];
      if (!known || (known.sandbox ?? true) !== sandbox) return new Response("{}", { status: 404 });
      if (m[1] === "transactions") {
        return Response.json({ signedTransactionInfo: jws(known.tx) });
      }
      return Response.json({
        data: [{ lastTransactions: [{
          originalTransactionId: known.tx.originalTransactionId,
          status: known.status ?? 1,
          signedTransactionInfo: jws(known.latest || known.tx),
          signedRenewalInfo: jws(known.renewal || { autoRenewStatus: 1 }),
        }] }],
      });
    }
    if (url === "https://oauth2.example/token") return Response.json({ access_token: "ya29.test" });
    if (url.startsWith("https://androidpublisher.googleapis.com")) {
      const m = url.match(/tokens\/([^/:]+)(:\w+)?$/);
      const token = decodeURIComponent(m[1]);
      if (m[2]) return new Response(null, { status: 204 });
      const known = google[token];
      return known ? Response.json(known) : new Response("{}", { status: 404 });
    }
    throw new Error(`unexpected fetch ${url}`);
  };
  const rpcAs = async (_env, token, fn, args) => {
    calls.push({ rpc: fn, as: token, args });
    if (fn === "store_verify_begin") {
      if (!admin) {
        const e = new Error("Seul un administrateur abonne l'entreprise à Mara Pro");
        e.status = 400;
        throw e;
      }
      return { org_id: args.p_org_id, user_id: OWNER, store_billing_on: true };
    }
    throw new Error(`unexpected rpcAs ${fn}`);
  };
  const rpcService = async (_env, fn, args) => {
    calls.push({ rpc: fn, service: true, args });
    if (fn === "store_settle") {
      // store_settle's own rules, as 128 has them (test_batch128 proves
      // them in SQL): the business, the token's owner, the sandbox, the order.
      if (gone.includes(args.p_org_id)) return { ok: false, reason: "no such business" };
      const key = `${args.p_platform}:${args.p_original_id}`;
      const had = db.get(key);
      if (had && had.org !== args.p_org_id) return { ok: false, reason: "another business" };
      if (args.p_environment === "sandbox" && !sandboxOk) return { ok: false, reason: "sandbox" };
      if (had?.signed && args.p_signed_at && Date.parse(args.p_signed_at) < Date.parse(had.signed)) {
        const pro = ["active", "grace", "cancelled"].includes(had.state) && Date.parse(had.expires) > Date.now();
        return { ok: true, stale: true, pro, state: had.state };
      }
      db.set(key, { org: args.p_org_id, state: args.p_state, expires: args.p_expires_at, product: args.p_product_id,
        env: args.p_environment, signed: args.p_signed_at || had?.signed });
      const pro = ["active", "grace", "cancelled"].includes(args.p_state) && Date.parse(args.p_expires_at) > Date.now();
      return { ok: true, pro, state: args.p_state };
    }
    if (fn === "store_org_of") {
      return db.get(`${args.p_platform}:${args.p_original_id}`)?.org ?? null;
    }
    if (fn === "store_due") {
      return [...db.entries()].map(([k, v]) => ({
        platform: k.split(":")[0], original_id: k.slice(k.indexOf(":") + 1),
        org_id: v.org, product_id: v.product, expires_at: v.expires, environment: v.env,
      }));
    }
    throw new Error(`unexpected rpcService ${fn}`);
  };
  return { io: { fetch: fetchImpl, rpcAs, rpcService, verify: VERIFY }, calls, db };
}

async function call(w, path, body, { token = "owner-jwt", e = env } = {}) {
  const url = new URL(`https://pay.example${path}`);
  const request = new Request(url, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify(body),
  });
  const response = await storeDoor(request, url, e, {}, w.io);
  return { status: response.status, body: await response.json() };
}

// ------------------------------------------------------------
// Apple's signature
// ------------------------------------------------------------

test("an App Store JWS verifies against its pinned root, and nothing else does", async () => {
  const payload = await verifyAppleJws(jws({ hello: "mara" }), VERIFY);
  assert.equal(payload.hello, "mara");

  // The real pin is Apple's: our test root is not Apple Root CA - G3.
  await assert.rejects(verifyAppleJws(jws({ a: 1 })), SignatureError);
  assert.equal(APPLE_ROOT_G3_SHA256.length, 64);

  // A payload changed after signing.
  const [h, , s] = jws({ productId: "bf.kaj.app.pro.monthly" }).split(".");
  const forged = `${h}.${b64u(JSON.stringify({ productId: "bf.kaj.app.pro.yearly" }))}.${s}`;
  await assert.rejects(verifyAppleJws(forged, VERIFY), /bad JWS signature/);

  // Signed by a chain whose leaf lacks Apple's mark, or whose intermediate does.
  const noLeaf = chain({ leafMark: false });
  await assert.rejects(verifyAppleJws(jws({ a: 1 }, noLeaf), { rootSha256: noLeaf.rootSha256 }), /signing certificate/);
  const noInter = chain({ interMark: false });
  await assert.rejects(verifyAppleJws(jws({ a: 1 }, noInter), { rootSha256: noInter.rootSha256 }), /intermediate/);

  // A leaf past its date.
  const old = chain({ leafNotAfter: new Date(Date.now() - 1000) });
  await assert.rejects(verifyAppleJws(jws({ a: 1 }, old), { rootSha256: old.rootSha256 }), /out of date/);

  // A chain whose intermediate was not signed by the root it shows.
  const a = chain();
  const b = chain();
  const mixed = { ...a, x5c: [a.x5c[0], a.x5c[1], b.x5c[2]] };
  await assert.rejects(verifyAppleJws(jws({ a: 1 }, mixed), { rootSha256: b.rootSha256 }), /bad certificate signature|broken chain/);

  // Not ES256.
  const none = `${b64u(JSON.stringify({ alg: "none", x5c: CHAIN.x5c }))}.${b64u("{}")}.`;
  await assert.rejects(verifyAppleJws(none, VERIFY), /ES256/);
});

test("Apple's statuses and Google's states map onto what store_settle keeps", () => {
  assert.equal(appleState(1, {}, { autoRenewStatus: 1 }), "active");
  assert.equal(appleState(1, {}, { autoRenewStatus: 0 }), "cancelled");
  assert.equal(appleState(2, {}, null), "expired");
  assert.equal(appleState(3, {}, null), "on_hold");
  assert.equal(appleState(4, {}, null), "grace");
  assert.equal(appleState(5, {}, null), "revoked");
  assert.equal(appleState(1, { revocationDate: 1 }, null), "revoked");
  assert.equal(googleState("SUBSCRIPTION_STATE_ACTIVE"), "active");
  assert.equal(googleState("SUBSCRIPTION_STATE_IN_GRACE_PERIOD"), "grace");
  assert.equal(googleState("SUBSCRIPTION_STATE_ON_HOLD"), "on_hold");
  assert.equal(googleState("SUBSCRIPTION_STATE_PAUSED"), "paused");
  assert.equal(googleState("SUBSCRIPTION_STATE_CANCELED"), "cancelled");
  assert.equal(googleState("SUBSCRIPTION_STATE_EXPIRED"), "expired");
  assert.equal(googleState("SUBSCRIPTION_STATE_PENDING"), "pending");
  assert.equal(googleState("SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED"), "expired");
  assert.equal(googleState("whatever"), "expired");
});

// ------------------------------------------------------------
// /store/verify — Apple
// ------------------------------------------------------------

test("Apple: a purchase for this business is asked of Apple, checked, and turns Pro on", async () => {
  const w = world({ apple: { 2000000111: { tx: tx() } } });
  const r = await call(w, "/store/verify", {
    platform: "apple", org_id: ORG, product_id: "bf.kaj.app.pro.monthly", transaction_id: "2000000111",
  });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.pro, true);
  assert.equal(r.body.state, "active");
  // Asked as the caller first, then production (404: unknown), then the sandbox.
  assert.equal(w.calls[0].rpc, "store_verify_begin");
  assert.equal(w.calls[0].as, "owner-jwt");
  const apple = w.calls.filter((c) => c.url?.startsWith("https://api.storekit"));
  assert.ok(apple[0].url.startsWith("https://api.storekit.itunes.apple.com/inApps/v1/transactions/2000000111"));
  assert.ok(apple[1].url.startsWith("https://api.storekit-sandbox.itunes.apple.com/inApps/v1/transactions/2000000111"));
  assert.ok(apple.some((c) => c.url.includes("/inApps/v1/subscriptions/2000000111")));
  // The bearer is an ES256 JWT for the bundle, with the key's id.
  const bearer = apple[0].headers.Authorization.slice(7);
  assert.deepEqual(decodeJwtPart(bearer.split(".")[0]), { alg: "ES256", kid: "KEY123", typ: "JWT" });
  const claims = decodeJwtPart(bearer.split(".")[1]);
  assert.equal(claims.aud, "appstoreconnect-v1");
  assert.equal(claims.bid, "bf.kaj.app");
  assert.equal(claims.iss, "issuer-uuid");
  // Written by the service role, by the original transaction id, sandbox.
  const settle = w.calls.find((c) => c.rpc === "store_settle");
  assert.equal(settle.service, true);
  assert.equal(settle.args.p_original_id, "2000000100");
  assert.equal(settle.args.p_environment, "sandbox");
  assert.equal(settle.args.p_bought_by, OWNER);
});

test("Apple: another business's purchase, another app's, another product, a refund", async () => {
  // appAccountToken names another business.
  let w = world({ apple: { 2000000111: { tx: tx({ appAccountToken: OTHER }) } } });
  let r = await call(w, "/store/verify", { platform: "apple", org_id: ORG, transaction_id: "2000000111" });
  assert.equal(r.status, 409);
  assert.equal(r.body.code, "wrong_org");
  assert.ok(!w.calls.some((c) => c.rpc === "store_settle"));

  // No appAccountToken at all.
  w = world({ apple: { 2000000111: { tx: tx({ appAccountToken: undefined }) } } });
  r = await call(w, "/store/verify", { platform: "apple", org_id: ORG, transaction_id: "2000000111" });
  assert.equal(r.status, 409);
  assert.equal(r.body.code, "no_org");

  // Another app's bundle.
  w = world({ apple: { 2000000111: { tx: tx({ bundleId: "com.other.app" }) } } });
  r = await call(w, "/store/verify", { platform: "apple", org_id: ORG, transaction_id: "2000000111" });
  assert.equal(r.status, 422);
  assert.equal(r.body.code, "bundle");

  // Another product of the same app.
  w = world({ apple: { 2000000111: { tx: tx({ productId: "bf.kaj.app.coins" }) } } });
  r = await call(w, "/store/verify", { platform: "apple", org_id: ORG, transaction_id: "2000000111" });
  assert.equal(r.status, 422);
  assert.equal(r.body.code, "product");

  // Refunded: revoked, no Pro.
  w = world({ apple: { 2000000111: { tx: tx({ revocationDate: Date.now() - 1000 }), status: 5 } } });
  r = await call(w, "/store/verify", { platform: "apple", org_id: ORG, transaction_id: "2000000111" });
  assert.equal(r.status, 200);
  assert.equal(r.body.state, "revoked");
  assert.equal(r.body.pro, false);

  // A transaction id that is not one.
  w = world();
  r = await call(w, "/store/verify", { platform: "apple", org_id: ORG, transaction_id: "../../x" });
  assert.equal(r.status, 400);

  // Unknown to Apple, in both environments.
  r = await call(w, "/store/verify", { platform: "apple", org_id: ORG, transaction_id: "999" });
  assert.equal(r.status, 404);
});

test("Apple: a grace period runs to its own end; billing retry gives nothing", async () => {
  const graceEnd = Date.now() + 6 * DAY;
  let w = world({ apple: { 2000000111: {
    tx: tx({ expiresDate: Date.now() - DAY }), status: 4,
    renewal: { autoRenewStatus: 1, gracePeriodExpiresDate: graceEnd },
  } } });
  let r = await call(w, "/store/verify", { platform: "apple", org_id: ORG, transaction_id: "2000000111" });
  assert.equal(r.body.state, "grace");
  assert.equal(r.body.pro, true);
  assert.equal(Date.parse(r.body.expires_at), graceEnd);

  w = world({ apple: { 2000000111: { tx: tx({ expiresDate: Date.now() - DAY }), status: 3 } } });
  r = await call(w, "/store/verify", { platform: "apple", org_id: ORG, transaction_id: "2000000111" });
  assert.equal(r.body.state, "on_hold");
  assert.equal(r.body.pro, false);
});

// ------------------------------------------------------------
// /store/verify — Google
// ------------------------------------------------------------

test("Google: an active purchase is read from Play, written, then acknowledged", async () => {
  const w = world({ google: { "tok-0123456789": sub() } });
  const r = await call(w, "/store/verify", { platform: "google", org_id: ORG, product_id: "mara_pro", token: "tok-0123456789" });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.pro, true);
  const urls = w.calls.filter((c) => c.url).map((c) => c.url);
  assert.equal(urls[0], "https://oauth2.example/token");
  assert.ok(urls.includes("https://androidpublisher.googleapis.com/androidpublisher/v3/applications/bf.kaj.app/purchases/subscriptionsv2/tokens/tok-0123456789"));
  const ack = w.calls.findIndex((c) => c.url?.endsWith("/purchases/subscriptions/mara_pro/tokens/tok-0123456789:acknowledge"));
  const settle = w.calls.findIndex((c) => c.rpc === "store_settle");
  assert.ok(ack > 0 && settle > 0 && ack > settle, "acknowledged after it is written");
  // The service account's assertion: RS256, for the androidpublisher scope.
  const tokenCall = w.calls.find((c) => c.url === "https://oauth2.example/token");
  const assertion = new URLSearchParams(tokenCall.body).get("assertion");
  assert.equal(decodeJwtPart(assertion.split(".")[0]).alg, "RS256");
  assert.equal(decodeJwtPart(assertion.split(".")[1]).scope, "https://www.googleapis.com/auth/androidpublisher");
  assert.equal(w.calls[settle].args.p_product_id, "mara_pro:monthly");
});

test("Google: every state; wrong business, wrong product, a token replayed for another", async () => {
  for (const [state, pro] of [
    ["SUBSCRIPTION_STATE_ACTIVE", true], ["SUBSCRIPTION_STATE_IN_GRACE_PERIOD", true],
    ["SUBSCRIPTION_STATE_CANCELED", true], ["SUBSCRIPTION_STATE_ON_HOLD", false],
    ["SUBSCRIPTION_STATE_PAUSED", false], ["SUBSCRIPTION_STATE_EXPIRED", false],
    ["SUBSCRIPTION_STATE_PENDING", false],
  ]) {
    const w = world({ google: { "tok-0123456789": sub({ subscriptionState: state }) } });
    const r = await call(w, "/store/verify", { platform: "google", org_id: ORG, token: "tok-0123456789" });
    assert.equal(r.status, 200, state);
    assert.equal(r.body.pro, pro, state);
    const acked = w.calls.some((c) => c.url?.endsWith(":acknowledge"));
    assert.equal(acked, !["SUBSCRIPTION_STATE_PENDING", "SUBSCRIPTION_STATE_EXPIRED"].includes(state), state);
  }
  // Expired by its date even while « active » at Google's last word.
  let w = world({ google: { "tok-0123456789": sub({ lineItems: [{ productId: "mara_pro", expiryTime: new Date(Date.now() - DAY).toISOString(), offerDetails: { basePlanId: "yearly" } }] }) } });
  let r = await call(w, "/store/verify", { platform: "google", org_id: ORG, token: "tok-0123456789" });
  assert.equal(r.body.pro, false);

  // The token names another business.
  w = world({ google: { "tok-0123456789": sub({ externalAccountIdentifiers: { obfuscatedExternalAccountId: OTHER } }) } });
  r = await call(w, "/store/verify", { platform: "google", org_id: ORG, token: "tok-0123456789" });
  assert.equal(r.status, 409);
  assert.equal(r.body.code, "wrong_org");

  // Another product, or a base plan Mara does not sell.
  w = world({ google: { "tok-0123456789": sub({ lineItems: [{ productId: "coins", expiryTime: new Date(Date.now() + DAY).toISOString() }] }) } });
  r = await call(w, "/store/verify", { platform: "google", org_id: ORG, token: "tok-0123456789" });
  assert.equal(r.status, 422);
  w = world({ google: { "tok-0123456789": sub({ lineItems: [{ productId: "mara_pro", expiryTime: new Date(Date.now() + DAY).toISOString(), offerDetails: { basePlanId: "weekly" } }] }) } });
  r = await call(w, "/store/verify", { platform: "google", org_id: ORG, token: "tok-0123456789" });
  assert.equal(r.status, 422);
  assert.equal(r.body.code, "base_plan");

  // Replayed: the same token, already written for ORG, sent by the owner
  // of OTHER (whose org id Google does not hold — so caught at once) —
  // and, were the store to say OTHER, by store_settle's own lock.
  w = world({ google: { "tok-0123456789": sub() } });
  r = await call(w, "/store/verify", { platform: "google", org_id: ORG, token: "tok-0123456789" });
  assert.equal(r.status, 200);
  r = await call(w, "/store/verify", { platform: "google", org_id: OTHER, token: "tok-0123456789" });
  assert.equal(r.status, 409);
  w.db.set("google:tok-9999999999", { org: OTHER });
  w.io.fetch = ((inner) => async (url, init) => (url.includes("tok-9999999999") && !url.endsWith(":acknowledge")
    ? Response.json(sub()) : inner(url, init)))(w.io.fetch);
  r = await call(w, "/store/verify", { platform: "google", org_id: ORG, token: "tok-9999999999" });
  assert.equal(r.status, 409);
  assert.equal(r.body.code, "replayed");
  // The same purchase twice for its own business: idempotent.
  r = await call(w, "/store/verify", { platform: "google", org_id: ORG, token: "tok-0123456789" });
  assert.equal(r.status, 200);
});

test("a caller who is not an administrator, or not signed in, gets nothing asked of the store", async () => {
  const w = world({ admin: false, google: { "tok-0123456789": sub() } });
  let r = await call(w, "/store/verify", { platform: "google", org_id: ORG, token: "tok-0123456789" });
  assert.equal(r.status, 403);
  assert.equal(r.body.code, "not_admin");
  assert.match(r.body.error, /administrateur/);
  assert.ok(!w.calls.some((c) => c.url), "neither Google nor Apple was asked");
  r = await call(w, "/store/verify", { platform: "google", org_id: ORG, token: "tok-0123456789" }, { token: null });
  assert.equal(r.status, 401);
  r = await call(w, "/store/verify", { platform: "steam", org_id: ORG });
  assert.equal(r.status, 400);
  r = await call(w, "/store/verify", { platform: "google", org_id: "nope" });
  assert.equal(r.status, 400);
  // Keys not installed yet: said, not guessed.
  r = await call(world(), "/store/verify", { platform: "apple", org_id: ORG, transaction_id: "1" },
    { e: { ...env, APPLE_IAP_PRIVATE_KEY: "" } });
  assert.equal(r.status, 503);
});

// ------------------------------------------------------------
// Notifications and the daily re-check
// ------------------------------------------------------------

test("App Store Server Notifications V2: verified, then Apple asked again; forged ones refused", async () => {
  // What Apple's API holds, by original transaction id; the test changes
  // it between notifications as Apple would.
  const apple = { 2000000100: { tx: tx({ transactionId: "2000000100" }), status: 1 } };
  const w = world({ apple });
  const note = (type, status, t = tx(), renewal = { autoRenewStatus: 1 }) => ({
    signedPayload: jws({
      notificationType: type,
      data: { bundleId: "bf.kaj.app", environment: "Sandbox", status,
        signedTransactionInfo: jws(t), signedRenewalInfo: jws(renewal) },
    }),
  });
  let r = await call(w, "/store/apple-notify", note("SUBSCRIBED", 1), { token: null });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.pro, true);
  assert.ok(w.calls.some((c) => c.url?.includes("/inApps/v1/subscriptions/2000000100")), "Apple's API was asked");
  // The payload says active; Apple now says expired: Apple is believed.
  apple[2000000100] = { tx: tx({ transactionId: "2000000100" }), status: 2,
    latest: tx({ expiresDate: Date.now() - DAY }) };
  r = await call(w, "/store/apple-notify", note("DID_RENEW", 1), { token: null });
  assert.equal(r.body.pro, false);
  assert.equal(w.db.get("apple:2000000100").state, "expired");
  // A renewal on a transaction with no appAccountToken: found by its id.
  apple[2000000100] = { tx: tx({ transactionId: "2000000100", appAccountToken: undefined }), status: 1 };
  r = await call(w, "/store/apple-notify", note("DID_RENEW", 1, tx({ appAccountToken: undefined, transactionId: "2000000222" })), { token: null });
  assert.equal(r.body.pro, true);
  assert.equal(w.calls.filter((c) => c.rpc === "store_org_of").length, 1);
  // Refund.
  apple[2000000100] = { tx: tx({ transactionId: "2000000100", revocationDate: Date.now() }), status: 5 };
  r = await call(w, "/store/apple-notify", note("REFUND", 5, tx({ revocationDate: Date.now() })), { token: null });
  assert.equal(r.body.state, "revoked");
  assert.equal(r.body.pro, false);
  // Every settle carries Apple's signedDate.
  assert.ok(w.calls.filter((c) => c.rpc === "store_settle").every((c) => typeof c.args.p_signed_at === "string"));
  // Apple's TEST.
  r = await call(w, "/store/apple-notify", { signedPayload: jws({ notificationType: "TEST" }) }, { token: null });
  assert.equal(r.body.test, true);
  // Forged: signed by somebody else's chain.
  const other = chain();
  r = await call(w, "/store/apple-notify", { signedPayload: jws({ notificationType: "SUBSCRIBED", data: {} }, other) }, { token: null });
  assert.equal(r.status, 401);
  // Another app's.
  r = await call(w, "/store/apple-notify", { signedPayload: jws({ notificationType: "SUBSCRIBED", data: { bundleId: "com.x" } }) }, { token: null });
  assert.equal(r.status, 422);
  // No App Store key on the Worker: nothing believed, Apple retries later.
  r = await call(w, "/store/apple-notify", note("DID_RENEW", 1), { token: null, e: { ...env, APPLE_IAP_PRIVATE_KEY: "" } });
  assert.equal(r.status, 503);
});

test("S1: a DID_RENEW replayed after a REFUND leaves Pro off", async () => {
  const apple = { 2000000100: { tx: tx({ transactionId: "2000000100" }), status: 1 } };
  const w = world({ apple });
  const note = (type, status, t) => ({ signedPayload: jws({ notificationType: type, signedDate: Date.now(),
    data: { bundleId: "bf.kaj.app", environment: "Sandbox", status, signedTransactionInfo: jws(t),
      signedRenewalInfo: jws({ autoRenewStatus: 1 }) } }) });
  const renew = note("DID_RENEW", 1, tx());
  let r = await call(w, "/store/apple-notify", renew, { token: null });
  assert.equal(r.body.pro, true);
  apple[2000000100] = { tx: tx({ transactionId: "2000000100", revocationDate: Date.now() }), status: 5 };
  r = await call(w, "/store/apple-notify", note("REFUND", 5, tx({ revocationDate: Date.now() })), { token: null });
  assert.equal(r.body.pro, false);
  r = await call(w, "/store/apple-notify", renew, { token: null }); // the same bytes, again
  assert.equal(r.status, 200);
  assert.equal(r.body.pro, false);
  assert.equal(r.body.state, "revoked");
  assert.equal(w.db.get("apple:2000000100").state, "revoked");
  // And an answer signed before the one held is not written (store_settle).
  const settles = w.calls.filter((c) => c.rpc === "store_settle");
  const older = { ...settles.at(-1).args, p_state: "active", p_signed_at: new Date(Date.now() - 3_600_000).toISOString() };
  const stale = await w.io.rpcService(env, "store_settle", older);
  assert.equal(stale.stale, true);
  assert.equal(stale.pro, false);
});

test("S2: a sandbox purchase for an ordinary business is refused, in French", async () => {
  const w = world({ sandboxOk: false, apple: { 2000000111: { tx: tx() } } });
  const r = await call(w, "/store/verify", { platform: "apple", org_id: ORG, transaction_id: "2000000111" });
  assert.equal(r.status, 403);
  assert.equal(r.body.code, "sandbox");
  assert.match(r.body.error, /Achat de test refusé/);
  assert.equal(w.db.size, 0);
  // Google's licence testers likewise.
  const g = world({ sandboxOk: false, google: { "tok-0123456789": sub({ testPurchase: {} }) } });
  const rg = await call(g, "/store/verify", { platform: "google", org_id: ORG, token: "tok-0123456789" });
  assert.equal(rg.status, 403);
  assert.equal(rg.body.code, "sandbox");
  assert.ok(!g.calls.some((c) => c.url?.endsWith(":acknowledge")), "not acknowledged");
});

test("S3: a purchase verified without naming the business is the store's business, for its admin only", async () => {
  let w = world({ apple: { 2000000111: { tx: tx() } } });
  let r = await call(w, "/store/verify", { platform: "apple", transaction_id: "2000000111" });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.org_id, ORG);
  const begin = w.calls.find((c) => c.rpc === "store_verify_begin");
  assert.equal(begin.args.p_org_id, ORG, "the caller must administer the business the store holds");
  assert.equal(w.calls.find((c) => c.rpc === "store_settle").args.p_org_id, ORG);
  // Not an administrator of it: refused, nothing written.
  w = world({ admin: false, apple: { 2000000111: { tx: tx({ appAccountToken: OTHER }) } } });
  r = await call(w, "/store/verify", { platform: "apple", transaction_id: "2000000111" });
  assert.equal(r.status, 403);
  assert.equal(r.body.code, "not_admin");
  assert.ok(!w.calls.some((c) => c.rpc === "store_settle"));
  // An expired session said as such, so the app keeps the purchase open.
  w = world({ apple: { 2000000111: { tx: tx() } } });
  w.io.rpcAs = async () => { const e = new Error("JWT expired"); e.status = 400; e.upstream = 401; throw e; };
  r = await call(w, "/store/verify", { platform: "apple", org_id: ORG, transaction_id: "2000000111" });
  assert.equal(r.status, 401);
  assert.equal(r.body.code, "session");
});

test("S7: notifications for a business that is gone, or another business's token: 200 ignored, logged", async () => {
  const logged = [];
  const warn = console.warn;
  console.warn = (...a) => logged.push(a.join(" "));
  try {
    const w = world({ gone: [ORG], apple: { 2000000100: { tx: tx({ transactionId: "2000000100" }), status: 1 } },
      google: { "tok-0123456789": sub() } });
    let r = await call(w, "/store/apple-notify", { signedPayload: jws({ notificationType: "DID_RENEW",
      data: { bundleId: "bf.kaj.app", status: 1, signedTransactionInfo: jws(tx()) } }) }, { token: null });
    assert.equal(r.status, 200);
    assert.equal(r.body.ignored, "no_business");
    const data = Buffer.from(JSON.stringify({ packageName: "bf.kaj.app", subscriptionNotification: { notificationType: 2, purchaseToken: "tok-0123456789" } })).toString("base64");
    r = await call(w, "/store/google-notify?secret=s3cret-pubsub", { message: { data } }, { token: null });
    assert.equal(r.status, 200);
    assert.equal(r.body.ignored, "no_business");
    // A transaction Apple does not know: ignored too.
    const u = world();
    r = await call(u, "/store/apple-notify", { signedPayload: jws({ notificationType: "DID_RENEW",
      data: { bundleId: "bf.kaj.app", status: 1, signedTransactionInfo: jws(tx()) } }) }, { token: null });
    assert.equal(r.status, 200);
    assert.ok(r.body.ignored);
    assert.ok(logged.some((l) => l.includes("apple-notify: ignored (no_business)")), logged.join("\n"));
    assert.ok(logged.some((l) => l.includes("google-notify: ignored (no_business)")));
    assert.ok(!logged.some((l) => l.includes("tok-0123456789")), "no token in the log");
  } finally {
    console.warn = warn;
  }
});

test("Google: a line with no base plan is not Mara Pro", async () => {
  const w = world({ google: { "tok-0123456789": sub({ lineItems: [{ productId: "mara_pro", expiryTime: new Date(Date.now() + 30 * DAY).toISOString(), offerDetails: {} }] }) } });
  const r = await call(w, "/store/verify", { platform: "google", org_id: ORG, token: "tok-0123456789" });
  assert.equal(r.status, 422);
  assert.equal(r.body.code, "base_plan");
  assert.ok(!w.calls.some((c) => c.rpc === "store_settle"));
});

test("Google RTDN: only with the secret; the token is read again from Google", async () => {
  const w = world({ google: { "tok-0123456789": sub({ subscriptionState: "SUBSCRIPTION_STATE_EXPIRED" }) } });
  w.db.set("google:tok-0123456789", { org: ORG, state: "active" });
  const push = (payload) => ({ message: { data: Buffer.from(JSON.stringify(payload)).toString("base64"), messageId: "1" }, subscription: "projects/x/subscriptions/y" });
  const rtdn = push({ packageName: "bf.kaj.app", subscriptionNotification: { notificationType: 13, purchaseToken: "tok-0123456789", subscriptionId: "mara_pro" } });
  let r = await call(w, "/store/google-notify", rtdn, { token: null });
  assert.equal(r.status, 401, "no secret");
  r = await call(w, "/store/google-notify?secret=wrong", rtdn, { token: null });
  assert.equal(r.status, 401, "wrong secret");
  r = await call(w, "/store/google-notify?secret=s3cret-pubsub", rtdn, { token: null });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.state, "expired");
  assert.equal(r.body.pro, false);
  assert.equal(w.db.get("google:tok-0123456789").state, "expired");
  // A test message, another app's, a token Google does not know: 200, nothing.
  r = await call(w, "/store/google-notify?secret=s3cret-pubsub", push({ packageName: "bf.kaj.app", testNotification: { version: "1.0" } }), { token: null });
  assert.equal(r.body.test, true);
  r = await call(w, "/store/google-notify?secret=s3cret-pubsub", push({ packageName: "com.x", subscriptionNotification: { purchaseToken: "tok-0123456789" } }), { token: null });
  assert.equal(r.body.ignored, true);
  r = await call(w, "/store/google-notify?secret=s3cret-pubsub", push({ packageName: "bf.kaj.app", subscriptionNotification: { notificationType: 4, purchaseToken: "tok-unknown-000" } }), { token: null });
  assert.equal(r.status, 200);
  assert.ok(r.body.ignored);
  // Unset on the Worker: every push refused.
  r = await call(w, "/store/google-notify?secret=", rtdn, { token: null, e: { ...env, GOOGLE_NOTIFY_SECRET: "" } });
  assert.equal(r.status, 401);
});

test("the daily re-check asks the store again and closes what it no longer knows", async () => {
  const w = world({
    google: { "tok-0123456789": sub({ lineItems: [{ productId: "mara_pro", expiryTime: new Date(Date.now() + 30 * DAY).toISOString(), offerDetails: { basePlanId: "monthly" } }] }) },
    apple: { 2000000100: { tx: tx({ transactionId: "2000000100" }), status: 2, latest: tx({ expiresDate: Date.now() - DAY }) } },
  });
  w.db.set("google:tok-0123456789", { org: ORG, state: "active", expires: new Date(Date.now() + DAY).toISOString(), product: "mara_pro:monthly", env: "production" });
  w.db.set("apple:2000000100", { org: ORG, state: "active", expires: new Date(Date.now() + DAY).toISOString(), product: "bf.kaj.app.pro.monthly", env: "sandbox" });
  w.db.set("google:tok-gone-00000", { org: ORG, state: "active", expires: new Date(Date.now() - DAY).toISOString(), product: "mara_pro:monthly", env: "production" });
  const result = await storeRecheck(env, w.io);
  assert.deepEqual(result, { due: 3, checked: 3, failed: 0 });
  // A failure is counted and logged by its code, never the token.
  const logged = [];
  const error = console.error;
  console.error = (...a) => logged.push(a.join(" "));
  try {
    const broken = world();
    broken.db.set("google:tok-0123456789", { org: ORG, state: "active", expires: new Date().toISOString(), product: "mara_pro:monthly", env: "production" });
    broken.io.fetch = async () => new Response("no", { status: 500 });
    assert.deepEqual(await storeRecheck(env, broken.io), { due: 1, checked: 0, failed: 1 });
  } finally {
    console.error = error;
  }
  assert.ok(logged.some((l) => l.startsWith("store recheck failed google 502")), logged.join("\n"));
  assert.ok(!logged.some((l) => l.includes("tok-0123456789")));
  assert.equal(w.db.get("google:tok-0123456789").state, "active", "renewed");
  assert.ok(Date.parse(w.db.get("google:tok-0123456789").expires) > Date.now() + 20 * DAY);
  assert.equal(w.db.get("apple:2000000100").state, "expired");
  assert.equal(w.db.get("google:tok-gone-00000").state, "expired");
});
