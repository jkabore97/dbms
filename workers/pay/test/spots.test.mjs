// Plays Google Play, the App Store, Stripe and the database against
// workers/pay's spot doors (139, batch 142): /store/spot-verify, the
// website's /v1/stripe/spot and the Stripe webhook's spot payments.
//
//   node --test workers/pay/test
//
// Apple's JWS are signed by a chain this file builds (as store.test.mjs
// does), so the verifier runs for real against the test's own pinned
// root. Nothing secret is committed: every key is generated here.

import assert from "node:assert/strict";
import { createHash, generateKeyPairSync, sign as nodeSign } from "node:crypto";
import { test } from "node:test";

import worker, { onStripeEvent, storeDoor } from "../src/index.js";
import { appleNotification } from "../src/apple.js";
import { priceLabel } from "../src/stripe.js";
import {
  APPLE_SPOT_PRODUCTS, GOOGLE_SPOT_PRODUCTS, isSpotEvent, isSpotProduct, stripeSpotCheckout,
} from "../src/spots.js";
import { hmacHex } from "../src/wave.js";

const ORG = "52000000-0000-0000-0000-0000000000a1";
const OTHER_ORG = "52000000-0000-0000-0000-0000000000b2";
const SPOT = "53000000-0000-0000-0000-0000000000c1";
const OTHER_SPOT = "53000000-0000-0000-0000-0000000000c2";
const OWNER = "51000000-0000-0000-0000-000000000001";

// ------------------------------------------------------------
// An Apple-like certificate chain, in a few lines of DER
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
function makeCert({ cn, issuerCn, key, issuerKey, hash, ca, marks = [] }) {
  const spki = key.publicKey.export({ type: "spki", format: "der" });
  const sigOid = hash === "sha384" ? "1.2.840.10045.4.3.3" : "1.2.840.10045.4.3.2";
  const exts = [
    seq(oid("2.5.29.19"), der(0x01, Buffer.from([0xff])), der(0x04, ca ? seq(der(0x01, Buffer.from([0xff]))) : seq())),
    ...marks.map((m) => seq(oid(m), der(0x04, Buffer.from([0x05, 0x00])))),
  ];
  const tbs = seq(der(0xa0, int(2)), int(7), seq(oid(sigOid)), name(issuerCn),
    seq(utc(new Date(Date.now() - 86_400_000)), utc(new Date(Date.now() + 365 * 86_400_000))),
    name(cn), spki, der(0xa3, seq(...exts)));
  const signature = nodeSign(hash, tbs, { key: issuerKey.privateKey, dsaEncoding: "der" });
  return seq(tbs, seq(oid(sigOid)), der(0x03, Buffer.concat([Buffer.from([0]), signature])));
}
const rootKey = generateKeyPairSync("ec", { namedCurve: "P-384" });
const interKey = generateKeyPairSync("ec", { namedCurve: "P-384" });
const leafKey = generateKeyPairSync("ec", { namedCurve: "P-256" });
const root = makeCert({ cn: "Test Root G3", issuerCn: "Test Root G3", key: rootKey, issuerKey: rootKey, hash: "sha384", ca: true });
const inter = makeCert({ cn: "Test WWDR G6", issuerCn: "Test Root G3", key: interKey, issuerKey: rootKey,
  hash: "sha384", ca: true, marks: ["1.2.840.113635.100.6.2.1"] });
const leaf = makeCert({ cn: "Test Prod ECC", issuerCn: "Test WWDR G6", key: leafKey, issuerKey: interKey,
  hash: "sha256", ca: false, marks: ["1.2.840.113635.100.6.11.1"] });
const X5C = [leaf, inter, root].map((c) => c.toString("base64"));
const VERIFY = { rootSha256: createHash("sha256").update(root).digest("hex") };
const b64u = (b) => Buffer.from(b).toString("base64url");
function jws(payload) {
  const head = b64u(JSON.stringify({ alg: "ES256", x5c: X5C }));
  const body = b64u(JSON.stringify(payload));
  const sig = nodeSign("sha256", Buffer.from(`${head}.${body}`), { key: leafKey.privateKey, dsaEncoding: "ieee-p1363" });
  return `${head}.${body}.${b64u(sig)}`;
}

// ------------------------------------------------------------
// The world: Google, Apple, Stripe and PostgREST, faked
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
  STRIPE_SECRET_KEY: "sk_test_mara",
  STRIPE_WEBHOOK_SECRET: "whsec_mara",
  APP_ORIGIN: "https://mara.example/",
};

const TOKEN = "gp-token-spot-0001.AO-J1Ox";
const purchase = (over = {}) => ({
  purchaseState: 0,
  consumptionState: 0,
  acknowledgementState: 0,
  orderId: "GPA.3300-1111-2222-33333",
  obfuscatedExternalAccountId: ORG,
  obfuscatedExternalProfileId: SPOT,
  regionCode: "BF",
  ...over,
});
const spotTx = (over = {}) => ({
  transactionId: "3000000111",
  originalTransactionId: "3000000111",
  bundleId: "bf.kaj.app",
  productId: "bf.kaj.app.spot.article7",
  type: "Consumable",
  appAccountToken: SPOT,
  environment: "Production",
  price: 1990,
  currency: "EUR",
  ...over,
});

/// spot_settle as 139 has it (test_batch139 proves it in SQL): one spot
/// per payment, the same payment the same spot, another spot refused.
function world({ google = {}, apple = {}, admin = true, sandboxOk = true, order = null,
  spot = { org_id: ORG, kind: "article" }, refuse = null, missing = false } = {}) {
  const calls = [];
  const paid = new Map();
  const refunded = new Set();
  const fetchImpl = async (url, init = {}) => {
    calls.push({ url, method: init.method, body: init.body, headers: init.headers });
    if (url === "https://oauth2.example/token") return Response.json({ access_token: "ya29.test" });
    if (url.startsWith("https://androidpublisher.googleapis.com")) {
      if (url.includes("/orders/")) {
        return order ? Response.json(order) : new Response("{}", { status: 403 });
      }
      const m = url.match(/products\/([^/]+)\/tokens\/([^/:]+)(:\w+)?$/);
      if (m[3]) return new Response("{}", { status: 200 });
      const known = google[`${decodeURIComponent(m[1])}:${decodeURIComponent(m[2])}`];
      return known ? Response.json(known) : new Response("{}", { status: 404 });
    }
    if (url.startsWith("https://api.storekit")) {
      const sandbox = url.includes("sandbox");
      const id = url.match(/transactions\/(\d+)/)[1];
      const known = apple[id];
      if (!known || (known.sandbox ?? false) !== sandbox) return new Response("{}", { status: 404 });
      return Response.json({ signedTransactionInfo: jws(known.tx) });
    }
    if (url.startsWith("https://api.stripe.com")) {
      const body = init.body ? Object.fromEntries(new URLSearchParams(init.body)) : null;
      calls[calls.length - 1].form = body;
      if (url.endsWith("/v1/refunds")) return Response.json({ id: "re_1", status: "succeeded" });
      if (url.endsWith("/v1/checkout/sessions")) return Response.json({ id: "cs_spot_1", url: "https://checkout.stripe.com/c/cs_spot_1" });
      const s = url.match(/checkout\/sessions\/([^/?]+)/);
      if (s) return Response.json(stripeSessions[decodeURIComponent(s[1])] || {});
      const pi = url.match(/payment_intents\/([^/?]+)\?expand%5B%5D=latest_charge$/);
      if (pi) return Response.json(stripeIntents[decodeURIComponent(pi[1])] || {});
    }
    throw new Error(`unexpected fetch ${url}`);
  };
  const rpcAs = async (_env, token, fn, args) => {
    calls.push({ rpc: fn, as: token, args });
    if (fn === "spot_verify_begin") {
      if (missing) return { promotion_id: args.p_promotion_id, missing: true, user_id: OWNER };
      if (!admin) {
        const e = new Error("Mise en avant introuvable");
        e.status = 400;
        throw e;
      }
      return { promotion_id: args.p_promotion_id, org_id: spot.org_id, kind: spot.kind, status: "requested", user_id: OWNER };
    }
    if (fn === "spot_stripe_begin") {
      return { promotion_id: args.p_promotion_id, org_id: ORG, org_name: "Maison Élégance", kind: "article",
        days: 7, label: "Robe de soirée", amount: 199, currency: "eur", price: 1.99, price_currency: "EUR",
        email: "contact@maison-elegance.example" };
    }
    throw new Error(`unexpected rpcAs ${fn}`);
  };
  const rpcService = async (_env, fn, args) => {
    calls.push({ rpc: fn, service: true, args });
    if (fn === "spot_settle") {
      const key = `${args.p_channel}:${args.p_external_id}`;
      if (args.p_environment === "sandbox" && !sandboxOk) return { ok: false, reason: "sandbox", recorded: true };
      if (refuse) return { ok: false, reason: refuse, recorded: true };
      if (missing) return { ok: false, reason: "no spot", recorded: true };
      const had = paid.get(key);
      if (had && had !== args.p_promotion_id) return { ok: false, reason: "another spot" };
      paid.set(key, args.p_promotion_id);
      return { ok: true, granted: !had, promotion_id: args.p_promotion_id, org_id: ORG,
        starts_at: "2026-10-14T10:00:00Z", ends_at: "2026-10-21T10:00:00Z" };
    }
    if (fn === "spot_refund") {
      const known = [...paid.keys()].some((k) => k === `${args.p_channel}:${args.p_external_id}`)
        || (args.p_channel === "stripe" && args.p_external_id === "pi_spot_1");
      if (!known) return { ok: true, already: false, tombstone: true, spot: "none" };
      const again = refunded.has(`${args.p_channel}:${args.p_external_id}`);
      refunded.add(`${args.p_channel}:${args.p_external_id}`);
      return { ok: true, already: again, promotion_id: SPOT, spot: "ended" };
    }
    throw new Error(`unexpected rpcService ${fn}`);
  };
  return { io: { fetch: fetchImpl, rpcAs, rpcService, verify: VERIFY }, calls, paid };
}
const stripeSessions = {};
const stripeIntents = {};

async function call(w, body, { token = "owner-jwt" } = {}) {
  const url = new URL("https://pay.example/store/spot-verify");
  const request = new Request(url, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify(body),
  });
  const response = await storeDoor(request, url, env, {}, w.io);
  return { status: response.status, body: await response.json() };
}

// ------------------------------------------------------------
// The products
// ------------------------------------------------------------
test("the four spot products are the owner's, and none of them is Mara Pro", () => {
  assert.deepEqual(GOOGLE_SPOT_PRODUCTS, { mara_spot_article_7: "article", mara_spot_shop_7: "shop" });
  assert.deepEqual(APPLE_SPOT_PRODUCTS, { "bf.kaj.app.spot.article7": "article", "bf.kaj.app.spot.shop7": "shop" });
  assert.ok(isSpotProduct("mara_spot_shop_7"));
  assert.ok(isSpotProduct("bf.kaj.app.spot.article7"));
  assert.ok(!isSpotProduct("mara_pro"));
  assert.ok(!isSpotProduct("bf.kaj.app.pro.monthly"));
});

// ------------------------------------------------------------
// Google Play
// ------------------------------------------------------------
test("Google: a paid consumable is read from purchases.products, programmed once, then acknowledged and consumed", async () => {
  const w = world({ google: { [`mara_spot_article_7:${TOKEN}`]: purchase() },
    order: { total: { currencyCode: "XOF", units: "1000", nanos: 0 } } });
  const r = await call(w, { platform: "google", promotion_id: SPOT, product_id: "mara_spot_article_7", token: TOKEN,
    price_amount: 999, price_currency: "XOF" });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.ok, true);
  assert.equal(r.body.granted, true);
  assert.equal(r.body.promotion_id, SPOT);
  // As the caller first, before Google is asked anything.
  assert.equal(w.calls[0].rpc, "spot_verify_begin");
  assert.equal(w.calls[0].as, "owner-jwt");
  const get = w.calls.find((c) => c.url?.includes(`/purchases/products/mara_spot_article_7/tokens/`) && c.method === "GET");
  assert.ok(get.url.startsWith("https://androidpublisher.googleapis.com/androidpublisher/v3/applications/bf.kaj.app/"));
  // Written by the service role, with what the order says was paid (not the app's 999).
  const settle = w.calls.find((c) => c.rpc === "spot_settle");
  assert.equal(settle.service, true);
  assert.equal(settle.args.p_channel, "google");
  assert.equal(settle.args.p_external_id, TOKEN);
  assert.equal(settle.args.p_promotion_id, SPOT);
  assert.equal(settle.args.p_amount, 1000);
  assert.equal(settle.args.p_currency, "XOF");
  assert.equal(settle.args.p_amount_source, "store");
  assert.equal(settle.args.p_environment, "production");
  assert.equal(settle.args.p_bought_by, OWNER);
  // Then acknowledged and consumed, after the spot is written.
  const settleAt = w.calls.indexOf(settle);
  const ack = w.calls.findIndex((c) => c.url?.endsWith(":acknowledge"));
  const consume = w.calls.findIndex((c) => c.url?.endsWith(":consume"));
  assert.ok(ack > settleAt && consume > ack, "ack then consume, after spot_settle");
});

test("Google: without the order's total, no amount is sent — the database writes Mara's own price, never the app's", async () => {
  const w = world({ google: { [`mara_spot_shop_7:${TOKEN}`]: purchase({ acknowledgementState: 1 }) },
    spot: { org_id: ORG, kind: "shop" } });
  const r = await call(w, { platform: "google", product_id: "mara_spot_shop_7", token: TOKEN,
    price_amount: 0.01, price_currency: "eur" });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  const settle = w.calls.find((c) => c.rpc === "spot_settle");
  assert.equal(settle.args.p_amount, null, "the app's 0.01 is never read");
  assert.equal(settle.args.p_currency, null);
  assert.equal(settle.args.p_amount_source, "mara");
  // The spot was read from the purchase itself (no promotion_id sent).
  assert.equal(settle.args.p_promotion_id, SPOT);
  // Already acknowledged: only consumed.
  assert.ok(!w.calls.some((c) => c.url?.endsWith(":acknowledge")));
  assert.ok(w.calls.some((c) => c.url?.endsWith(":consume")));
});

test("Google: the same token again is the same spot — granted once, never twice", async () => {
  const w = world({ google: { [`mara_spot_article_7:${TOKEN}`]: purchase() } });
  const body = { platform: "google", promotion_id: SPOT, product_id: "mara_spot_article_7", token: TOKEN };
  const first = await call(w, body);
  const again = await call(w, body);
  assert.equal(first.body.granted, true);
  assert.equal(again.status, 200);
  assert.equal(again.body.granted, false, "shown again, nothing more is granted");
  assert.equal(w.paid.size, 1);
});

test("Google: a token replayed for another spot is refused for good (replayed)", async () => {
  const w = world({ google: { [`mara_spot_article_7:${TOKEN}`]: purchase() } });
  await call(w, { platform: "google", product_id: "mara_spot_article_7", token: TOKEN });
  // The same token, now said to be another spot's: Google's purchase still
  // names SPOT, so the Worker refuses before the database.
  const r = await call(w, { platform: "google", promotion_id: OTHER_SPOT, product_id: "mara_spot_article_7", token: TOKEN });
  assert.equal(r.status, 409);
  assert.equal(r.body.code, "wrong_spot");
  // And a purchase whose store says another spot than the one already paid with this token.
  const w2 = world({ google: { [`mara_spot_article_7:${TOKEN}`]: purchase({ obfuscatedExternalProfileId: OTHER_SPOT }) } });
  w2.paid.set(`google:${TOKEN}`, SPOT);
  const r2 = await call(w2, { platform: "google", product_id: "mara_spot_article_7", token: TOKEN });
  assert.equal(r2.status, 409);
  assert.equal(r2.body.code, "replayed");
  assert.ok(!w2.calls.some((c) => c.url?.endsWith(":consume")), "nothing consumed for a refusal");
});

test("Google: pending, cancelled, another business, not a spot, a test card — each refused with its code, nothing written", async () => {
  const cases = [
    [purchase({ purchaseState: 2 }), "mara_spot_article_7", 202, "pending"],
    [purchase({ purchaseState: 1 }), "mara_spot_article_7", 409, "cancelled"],
    [purchase({ obfuscatedExternalAccountId: OTHER_ORG }), "mara_spot_article_7", 409, "wrong_org"],
    [purchase({ obfuscatedExternalProfileId: undefined }), "mara_spot_article_7", 409, "no_spot"],
    [purchase(), "mara_pro", 422, "product"],
  ];
  for (const [p, product, status, code] of cases) {
    const w = world({ google: { [`${product}:${TOKEN}`]: p } });
    const r = await call(w, { platform: "google", product_id: product, token: TOKEN });
    assert.equal(r.status, status, `${code}: ${JSON.stringify(r.body)}`);
    assert.equal(r.body.code, code);
    assert.ok(!w.calls.some((c) => c.rpc === "spot_settle"), `${code}: nothing written`);
    assert.ok(!w.calls.some((c) => c.url?.endsWith(":consume")), `${code}: nothing consumed`);
  }
  // A licence tester's purchase, for a business that is not a test account's.
  const w = world({ google: { [`mara_spot_article_7:${TOKEN}`]: purchase({ purchaseType: 0 }) }, sandboxOk: false });
  const r = await call(w, { platform: "google", product_id: "mara_spot_article_7", token: TOKEN });
  assert.equal(r.status, 403);
  assert.equal(r.body.code, "sandbox");
  assert.equal(w.calls.find((c) => c.rpc === "spot_settle").args.p_environment, "sandbox");
  // An article purchase for a whole-vitrine spot.
  const w3 = world({ google: { [`mara_spot_article_7:${TOKEN}`]: purchase() }, spot: { org_id: ORG, kind: "shop" } });
  const r3 = await call(w3, { platform: "google", product_id: "mara_spot_article_7", token: TOKEN });
  assert.equal(r3.body.code, "product");
});

test("the caller must administer the spot's business; a session is needed", async () => {
  const w = world({ google: { [`mara_spot_article_7:${TOKEN}`]: purchase() }, admin: false });
  const r = await call(w, { platform: "google", promotion_id: SPOT, product_id: "mara_spot_article_7", token: TOKEN });
  assert.equal(r.status, 403);
  assert.equal(r.body.code, "not_admin");
  assert.ok(!w.calls.some((c) => c.url?.includes("androidpublisher")), "the store is not asked for a stranger");
  const none = await call(world(), { platform: "google", token: TOKEN }, { token: "" });
  assert.equal(none.status, 401);
  const bad = await call(world(), { platform: "web", token: TOKEN });
  assert.equal(bad.body.code, "platform");
});

// ------------------------------------------------------------
// The App Store
// ------------------------------------------------------------
test("Apple: a consumable's signed transaction is verified, its price and currency kept", async () => {
  const w = world({ apple: { 3000000111: { tx: spotTx() } } });
  const r = await call(w, { platform: "apple", promotion_id: SPOT, product_id: "bf.kaj.app.spot.article7",
    transaction_id: "3000000111" });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.granted, true);
  const settle = w.calls.find((c) => c.rpc === "spot_settle");
  assert.equal(settle.args.p_channel, "apple");
  assert.equal(settle.args.p_external_id, "3000000111");
  assert.equal(settle.args.p_amount, 1.99, "Apple's milli-units");
  assert.equal(settle.args.p_currency, "EUR");
  assert.equal(settle.args.p_amount_source, "store");
  assert.equal(settle.args.p_environment, "production");
  // Nothing to acknowledge at Apple: the app finishes the transaction.
  assert.ok(!w.calls.some((c) => c.url?.includes("androidpublisher")));
});

test("Apple: another app's, Mara Pro's, a refunded or another spot's transaction is refused for good", async () => {
  const cases = [
    [spotTx({ bundleId: "com.other" }), 422, "bundle"],
    [spotTx({ productId: "bf.kaj.app.pro.monthly" }), 422, "product"],
    [spotTx({ revocationDate: Date.now() }), 409, "revoked"],
    [spotTx({ appAccountToken: OTHER_SPOT }), 409, "wrong_spot"],
  ];
  for (const [t, status, code] of cases) {
    const w = world({ apple: { 3000000111: { tx: t } } });
    const r = await call(w, { platform: "apple", promotion_id: SPOT, transaction_id: "3000000111" });
    assert.equal(r.status, status, code);
    assert.equal(r.body.code, code);
    assert.ok(!w.calls.some((c) => c.rpc === "spot_settle"));
  }
  const w = world();
  const r = await call(w, { platform: "apple", promotion_id: SPOT, transaction_id: "12ab" });
  assert.equal(r.body.code, "transaction");
});

test("Apple: a TestFlight purchase is a sandbox one; refused unless the business is a test account's", async () => {
  const w = world({ apple: { 3000000111: { tx: spotTx({ environment: "Sandbox" }), sandbox: true } }, sandboxOk: false });
  const r = await call(w, { platform: "apple", promotion_id: SPOT, transaction_id: "3000000111" });
  assert.equal(r.body.code, "sandbox");
  const ok = world({ apple: { 3000000111: { tx: spotTx({ environment: "Sandbox" }), sandbox: true } } });
  assert.equal((await call(ok, { platform: "apple", promotion_id: SPOT, transaction_id: "3000000111" })).status, 200);
});

test("Apple's notifications about a spot change no subscription and are answered", async () => {
  const note = await appleNotification(env, {
    signedPayload: jws({ notificationType: "REFUND", data: { bundleId: "bf.kaj.app", signedTransactionInfo: jws(spotTx()) } }),
  }, VERIFY);
  assert.equal(note.settlement, undefined);
  assert.match(note.ignored, /^spot REFUND/);
  // Without Apple's revocationDate, a « REFUND » is not believed.
  assert.equal(note.spotRefund, undefined);
  const other = await appleNotification(env, {
    signedPayload: jws({ notificationType: "CONSUMPTION_REQUEST", data: { bundleId: "bf.kaj.app", signedTransactionInfo: jws(spotTx()) } }),
  }, VERIFY);
  assert.equal(other.spotRefund, undefined);
  assert.match(other.ignored, /^spot CONSUMPTION_REQUEST/);
});

// ------------------------------------------------------------
// A payment taken back
// ------------------------------------------------------------
async function door(w, path, body) {
  const url = new URL(`https://pay.example${path}`);
  const request = new Request(url, { method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body) });
  const response = await storeDoor(request, url, { ...env, GOOGLE_NOTIFY_SECRET: "pubsub-secret" }, {}, w.io);
  return { status: response.status, body: await response.json() };
}

test("Apple's REFUND of a spot (signed, revoked) ends it once; another app's refund is refused", async () => {
  const w = world();
  w.paid.set("apple:3000000111", SPOT);
  const refund = { signedPayload: jws({ notificationType: "REFUND",
    data: { bundleId: "bf.kaj.app", signedTransactionInfo: jws(spotTx({ revocationDate: Date.now(), revocationReason: 0 })) } }) };
  const first = await door(w, "/store/apple-notify", refund);
  assert.equal(first.status, 200, JSON.stringify(first.body));
  assert.deepEqual(first.body, { refunded: true, already: false, promotion_id: SPOT, spot: "ended" });
  const call = w.calls.find((c) => c.rpc === "spot_refund");
  assert.equal(call.service, true);
  assert.deepEqual(call.args, { p_channel: "apple", p_external_id: "3000000111", p_reason: "apple REFUND" });
  assert.equal((await door(w, "/store/apple-notify", refund)).body.already, true, "told twice, once");
  // Signed for another app: never a spot of Mara's.
  const foreign = await door(w, "/store/apple-notify", { signedPayload: jws({ notificationType: "REFUND",
    data: { bundleId: "com.other.app", signedTransactionInfo: jws(spotTx({ bundleId: "com.other.app", revocationDate: Date.now() })) } }) });
  assert.notEqual(foreign.status, 200);
  assert.equal(w.calls.filter((c) => c.rpc === "spot_refund").length, 2);
});

test("Google's voided one-time purchase ends its spot; a subscription's voided one and a bad secret do not", async () => {
  const w = world();
  w.paid.set(`google:${TOKEN}`, SPOT);
  const push = (n) => ({ message: { data: Buffer.from(JSON.stringify({ packageName: "bf.kaj.app", ...n })).toString("base64") } });
  const voided = push({ voidedPurchaseNotification: { purchaseToken: TOKEN, orderId: "GPA.3300-1111-2222-33333", productType: 2, refundType: 1 } });
  const r = await door(w, "/store/google-notify?secret=pubsub-secret", voided);
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.refunded, true);
  assert.deepEqual(w.calls.find((c) => c.rpc === "spot_refund").args,
    { p_channel: "google", p_external_id: TOKEN, p_reason: "google voided (1)" });
  // A subscription's (Mara Pro's): not a spot's.
  const sub = await door(w, "/store/google-notify?secret=pubsub-secret",
    push({ voidedPurchaseNotification: { purchaseToken: "sub-token-0000000001", productType: 1 } }));
  assert.equal(sub.body.ignored, true);
  // A token not settled yet: its mark, so it never programs a spot.
  const early = await door(w, "/store/google-notify?secret=pubsub-secret",
    push({ voidedPurchaseNotification: { purchaseToken: "other-token-00000001", productType: 2 } }));
  assert.deepEqual(early.body, { refunded: true, already: false, promotion_id: null, spot: "none" });
  // Without the secret: refused before anything.
  const bad = await door(w, "/store/google-notify?secret=nope", voided);
  assert.equal(bad.status, 401);
  assert.equal(w.calls.filter((c) => c.rpc === "spot_refund").length, 2);
});

test("Stripe: a spot's full refund or dispute, read again from Stripe, ends it; a partial refund or Mara Pro's charge nothing", async () => {
  stripeIntents.pi_spot_1 = { id: "pi_spot_1", metadata: { kind: "spot", promotion_id: SPOT },
    latest_charge: { id: "ch_1", refunded: true, disputed: false } };
  stripeIntents.pi_spot_2 = { id: "pi_spot_2", metadata: { kind: "spot", promotion_id: SPOT },
    latest_charge: { id: "ch_2", refunded: false, amount_refunded: 100, disputed: false } };
  stripeIntents.pi_pro_1 = { id: "pi_pro_1", metadata: {}, latest_charge: { id: "ch_3", refunded: true } };
  const w = world();
  const ev = (type, pi) => ({ type, data: { object: { id: "ch_x", object: type === "charge.refunded" ? "charge" : "dispute",
    payment_intent: pi, refunded: true } } });
  const out = await onStripeEvent(ev("charge.refunded", "pi_spot_1"), env, w.io);
  assert.deepEqual(out, { refunded: true, already: false, promotion_id: SPOT, spot: "ended" });
  assert.deepEqual(w.calls.find((c) => c.rpc === "spot_refund").args,
    { p_channel: "stripe", p_external_id: "pi_spot_1", p_reason: "stripe charge.refunded" });
  // The event says refunded, Stripe's copy a partial refund: nothing.
  assert.deepEqual(await onStripeEvent(ev("charge.refunded", "pi_spot_2"), env, w.io), { ignored: "partial refund" });
  // Not disputed by Stripe's own copy: nothing.
  assert.deepEqual(await onStripeEvent(ev("charge.dispute.created", "pi_spot_2"), env, w.io), { ignored: "not disputed" });
  // Mara Pro's charge: not a spot.
  assert.deepEqual(await onStripeEvent(ev("charge.refunded", "pi_pro_1"), env, w.io), { ignored: "not a spot" });
  assert.equal(w.calls.filter((c) => c.rpc === "spot_refund").length, 1);
  // A dispute Stripe confirms ends it too.
  stripeIntents.pi_spot_1.latest_charge.disputed = true;
  assert.equal((await onStripeEvent(ev("charge.dispute.created", "pi_spot_1"), env, w.io)).refunded, true);
});

// ------------------------------------------------------------
// Stripe, on the website
// ------------------------------------------------------------
test("Stripe: a spot's one-time Checkout is the database's amount and currency, never the app's", async () => {
  const w = world();
  const out = await stripeSpotCheckout({ promotion_id: SPOT, amount: 1 }, "owner-jwt", env, w.io);
  assert.deepEqual(out, { url: "https://checkout.stripe.com/c/cs_spot_1", id: "cs_spot_1" });
  const begin = w.calls[0];
  assert.equal(begin.rpc, "spot_stripe_begin");
  assert.deepEqual(begin.args, { p_promotion_id: SPOT }, "the app's amount is not sent");
  const p = w.calls.find((c) => c.url?.endsWith("/v1/checkout/sessions")).form;
  assert.equal(p.mode, "payment");
  assert.equal(p["line_items[0][price_data][unit_amount]"], "199");
  assert.equal(p["line_items[0][price_data][currency]"], "eur");
  assert.equal(p["line_items[0][price_data][product_data][name]"],
    "Mara · Un article à la une, 7 jours · Robe de soirée · 1,99 EUR · Maison Élégance");
  assert.equal(p["metadata[kind]"], "spot");
  assert.equal(p["metadata[promotion_id]"], SPOT);
  assert.equal(p.client_reference_id, SPOT);
  assert.equal(p.success_url, `https://mara.example/o/${ORG}/administration/parametres?partie=vitrine&spot=ok`);
  assert.equal(p.cancel_url, `https://mara.example/o/${ORG}/administration/parametres?partie=vitrine&spot=annule`);
});

test("Stripe: the webhook programs a paid spot from Stripe's own copy, once; an unpaid or foreign session nothing", async () => {
  stripeSessions.cs_spot_1 = { id: "cs_spot_1", mode: "payment", payment_status: "paid", livemode: true,
    amount_total: 1000, currency: "xof", metadata: { kind: "spot", promotion_id: SPOT, spot_kind: "article" } };
  stripeSessions.cs_spot_2 = { id: "cs_spot_2", mode: "payment", payment_status: "unpaid", livemode: true,
    amount_total: 499, currency: "usd", metadata: { kind: "spot", promotion_id: SPOT, spot_kind: "shop" } };
  const event = (id) => ({ type: "checkout.session.completed",
    data: { object: { id, mode: "payment", metadata: { kind: "spot" }, payment_status: "paid" } } });
  assert.ok(isSpotEvent(event("cs_spot_1")));
  assert.ok(!isSpotEvent({ type: "checkout.session.completed", data: { object: { mode: "subscription" } } }));

  const w = world();
  const out = await onStripeEvent(event("cs_spot_1"), env, w.io);
  assert.deepEqual(out, { settled: true, granted: true, promotion_id: SPOT });
  const settle = w.calls.find((c) => c.rpc === "spot_settle");
  assert.equal(settle.service, true);
  assert.equal(settle.args.p_channel, "stripe");
  assert.equal(settle.args.p_external_id, "cs_spot_1");
  assert.equal(settle.args.p_product_id, "stripe:article");
  assert.equal(settle.args.p_amount, 1000, "XOF is zero-decimal");
  assert.equal(settle.args.p_currency, "XOF");
  // Delivered twice: the same spot, nothing more.
  assert.equal((await onStripeEvent(event("cs_spot_1"), env, w.io)).granted, false);
  // The event says paid, Stripe's copy does not: nothing.
  assert.deepEqual(await onStripeEvent(event("cs_spot_2"), env, w.io), { ignored: "payment unpaid" });
  assert.equal(w.calls.filter((c) => c.rpc === "spot_settle").length, 2);
});

test("Stripe: the webhook door takes a signed spot event; a test-mode one is a sandbox payment", async () => {
  stripeSessions.cs_spot_3 = { id: "cs_spot_3", mode: "payment", payment_status: "paid", livemode: false,
    amount_total: 499, currency: "usd", metadata: { kind: "spot", promotion_id: SPOT, spot_kind: "shop" } };
  const w = world({ sandboxOk: false, spot: { org_id: ORG, kind: "shop" } });
  const out = await onStripeEvent({ type: "checkout.session.completed",
    data: { object: { id: "cs_spot_3", mode: "payment", metadata: { kind: "spot" } } } }, env, w.io);
  assert.deepEqual(out, { ignored: "sandbox" }, "answered 200, never retried");
  const settle = w.calls.find((c) => c.rpc === "spot_settle");
  assert.equal(settle.args.p_amount, 4.99);
  assert.equal(settle.args.p_currency, "USD");
  assert.equal(settle.args.p_environment, "sandbox");

  // Through the real door: a bad signature is refused.
  const body = JSON.stringify({ type: "checkout.session.completed", data: { object: { id: "cs_spot_3", mode: "payment", metadata: { kind: "spot" } } } });
  const bad = await worker.fetch(new Request("https://pay.example/v1/stripe", {
    method: "POST", body, headers: { "Stripe-Signature": "t=1,v1=00" } }), env);
  assert.equal(bad.status, 401);
  const t = Math.floor(Date.now() / 1000);
  assert.ok((await hmacHex(env.STRIPE_WEBHOOK_SECRET, `${t}.${body}`)).length === 64);
});

test("the spot's card door needs the Stripe key and a session", async () => {
  const off = await worker.fetch(new Request("https://pay.example/v1/stripe/spot", {
    method: "POST", body: "{}", headers: { Authorization: "Bearer t" } }), { ...env, STRIPE_SECRET_KEY: "" });
  assert.equal(off.status, 503);
  const anon = await worker.fetch(new Request("https://pay.example/v1/stripe/spot", {
    method: "POST", body: "{}" }), env);
  assert.equal(anon.status, 401);
});

test("the price on Stripe's page reads as the app says it: francs whole, euros and dollars to the cent", () => {
  assert.equal(priceLabel(1000, "XOF"), "1 000 FCFA");
  assert.equal(priceLabel(2500, "XAF"), "2 500 FCFA");
  assert.equal(priceLabel(1.99, "EUR"), "1,99 EUR");
  assert.equal(priceLabel(49.9, "USD"), "49,90 USD");
  assert.equal(priceLabel(5, "USD"), "5 USD");
});

test("Stripe: a session refunded before its settle leaves its mark and programs nothing", async () => {
  stripeSessions.cs_spot_r = { id: "cs_spot_r", mode: "payment", payment_status: "paid", livemode: true,
    amount_total: 5000, currency: "xof", payment_intent: "pi_spot_r",
    metadata: { kind: "spot", promotion_id: SPOT, spot_kind: "article" } };
  stripeIntents.pi_spot_r = { id: "pi_spot_r", metadata: { kind: "spot" }, latest_charge: { refunded: true } };
  const w = world();
  const out = await onStripeEvent({ type: "checkout.session.completed",
    data: { object: { id: "cs_spot_r", mode: "payment", metadata: { kind: "spot" } } } }, env, w.io);
  assert.deepEqual(out, { ignored: "refunded" });
  assert.ok(!w.calls.some((c) => c.rpc === "spot_settle"));
  assert.deepEqual(w.calls.find((c) => c.rpc === "spot_refund").args,
    { p_channel: "stripe", p_external_id: "pi_spot_r", p_reason: "stripe refunded before settle" });
});

test("Stripe: a payment refused for good (the spot refused, gone, no longer eligible) is refunded at once and written", async () => {
  stripeSessions.cs_spot_x = { id: "cs_spot_x", mode: "payment", payment_status: "paid", livemode: true,
    amount_total: 5000, currency: "xof", payment_intent: "pi_spot_x",
    metadata: { kind: "spot", promotion_id: SPOT, spot_kind: "article" } };
  stripeIntents.pi_spot_x = { id: "pi_spot_x", metadata: { kind: "spot" }, latest_charge: { refunded: false } };
  for (const reason of ["refused", "no spot", "article"]) {
    const w = world({ refuse: reason });
    const out = await onStripeEvent({ type: "checkout.session.completed",
      data: { object: { id: "cs_spot_x", mode: "payment", metadata: { kind: "spot" } } } }, env, w.io);
    assert.equal(out.refunded, true, reason);
    const refund = w.calls.find((c) => c.url?.endsWith("/v1/refunds"));
    assert.equal(refund.form.payment_intent, "pi_spot_x");
    assert.equal(refund.headers["Idempotency-Key"], "mara-spot-refund-pi_spot_x");
    const marked = w.calls.find((c) => c.rpc === "spot_refund");
    assert.equal(marked.args.p_external_id, "cs_spot_x");
    assert.match(marked.args.p_reason, /auto-refund/);
  }
});

test("Apple: a spot gone (its business deleted) is written for the platform to refund, and refused for good", async () => {
  const w = world({ missing: true, apple: { 3000000111: { tx: spotTx() } } });
  const r = await call(w, { platform: "apple", promotion_id: SPOT, transaction_id: "3000000111" });
  assert.equal(r.status, 404);
  assert.equal(r.body.code, "no_spot");
  assert.ok(w.calls.some((c) => c.rpc === "spot_settle"), "spot_settle wrote it");
});

test("Google: the purchase's business rides to spot_settle, which checks it is the spot's", async () => {
  const w = world({ google: { [`mara_spot_article_7:${TOKEN}`]: purchase() } });
  await call(w, { platform: "google", promotion_id: SPOT, product_id: "mara_spot_article_7", token: TOKEN });
  assert.equal(w.calls.find((c) => c.rpc === "spot_settle").args.p_org_id, ORG);
});

test("Google's PURCHASED notification of a spot (a pending one completed, the app closed) programs it, then acknowledges and consumes", async () => {
  const w = world({ google: { [`mara_spot_shop_7:${TOKEN}`]: purchase() }, spot: { org_id: ORG, kind: "shop" } });
  const push = (n) => ({ message: { data: Buffer.from(JSON.stringify({ packageName: "bf.kaj.app", ...n })).toString("base64") } });
  const r = await door(w, "/store/google-notify?secret=pubsub-secret",
    push({ oneTimeProductNotification: { notificationType: 1, purchaseToken: TOKEN, sku: "mara_spot_shop_7" } }));
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.settled, true);
  const settle = w.calls.find((c) => c.rpc === "spot_settle");
  assert.equal(settle.args.p_promotion_id, SPOT);
  assert.equal(settle.args.p_org_id, ORG);
  assert.equal(settle.args.p_bought_by, null);
  assert.ok(w.calls.some((c) => c.url?.endsWith(":consume")));
  // Pending or cancelled at Google: nothing.
  const w2 = world({ google: { [`mara_spot_shop_7:${TOKEN}`]: purchase({ purchaseState: 2 }) } });
  const pending = await door(w2, "/store/google-notify?secret=pubsub-secret",
    push({ oneTimeProductNotification: { notificationType: 1, purchaseToken: TOKEN, sku: "mara_spot_shop_7" } }));
  assert.deepEqual(pending.body, { ignored: "pending" });
  assert.ok(!w2.calls.some((c) => c.rpc === "spot_settle"));
  // Refused for good: never acknowledged (Google refunds it).
  const w3 = world({ refuse: "refused", google: { [`mara_spot_shop_7:${TOKEN}`]: purchase() } });
  const refused = await door(w3, "/store/google-notify?secret=pubsub-secret",
    push({ oneTimeProductNotification: { notificationType: 1, purchaseToken: TOKEN, sku: "mara_spot_shop_7" } }));
  assert.equal(refused.status, 200);
  assert.ok(!w3.calls.some((c) => c.url?.endsWith(":acknowledge") || c.url?.endsWith(":consume")));
});
