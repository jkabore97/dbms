// Mara Pro bought in the iPhone app: what Apple says about it (130).
//
// The App Store Server API, signed with an In-App Purchase key (ES256 JWT:
// APPLE_IAP_KEY_ID, APPLE_IAP_ISSUER_ID, APPLE_IAP_PRIVATE_KEY — the .p8's
// text — for the bundle APPLE_BUNDLE_ID, bf.kaj.app by default):
//
//   GET /inApps/v1/transactions/{id}    the purchase the app reported
//   GET /inApps/v1/subscriptions/{id}   where its subscription stands now
//
// Production first, then the sandbox (TestFlight, App Review) when
// production does not know the transaction. Every answer is a JWS, checked
// against Apple Root CA - G3 (x509.js) before a word of it is believed.
//
// And App Store Server Notifications V2 (POST /store/apple-notify): a
// signedPayload, checked the same way, whose transaction and renewal are
// themselves JWS.

import { signEs256 } from "./jwt.js";
import { verifyAppleJws } from "./x509.js";

// The global fetch, called as a plain function: a Worker throws « Illegal
// invocation » when it is called as io.fetch(…) with io as `this` (the
// first Google check failed so).
const callFetch = (input, init) => fetch(input, init);

export const APPLE_PRODUCTS = ["bf.kaj.app.pro.monthly", "bf.kaj.app.pro.yearly"];
const HOSTS = {
  production: "https://api.storekit.itunes.apple.com",
  sandbox: "https://api.storekit-sandbox.itunes.apple.com",
};

export class StoreError extends Error {
  /// [detail]: what the store itself said — for the Worker's log only,
  /// never answered to the app (SEC_AUDIT_2 L1).
  constructor(message, status = 400, code = "", detail = "") {
    super(message);
    this.status = status;
    this.code = code;
    this.detail = detail;
  }
}

export const appleBundle = (env) => env.APPLE_BUNDLE_ID || "bf.kaj.app";

export function appleConfigured(env) {
  return Boolean(env.APPLE_IAP_KEY_ID && env.APPLE_IAP_ISSUER_ID && env.APPLE_IAP_PRIVATE_KEY);
}

/// The API's bearer token: five minutes, for this bundle.
export async function appleToken(env, now = Date.now()) {
  const iat = Math.floor(now / 1000);
  return signEs256({ kid: env.APPLE_IAP_KEY_ID, typ: "JWT" }, {
    iss: env.APPLE_IAP_ISSUER_ID,
    iat,
    exp: iat + 300,
    aud: "appstoreconnect-v1",
    bid: appleBundle(env),
  }, env.APPLE_IAP_PRIVATE_KEY);
}

async function appleGet(env, path, io) {
  const token = await appleToken(env, io.now?.());
  let last = null;
  for (const environment of ["production", "sandbox"]) {
    const response = await io.fetch(`${HOSTS[environment]}${path}`, {
      method: "GET",
      headers: { Authorization: `Bearer ${token}` },
    });
    if (response.status === 404) {
      last = response;
      continue;
    }
    const text = await response.text();
    if (!response.ok) {
      throw new StoreError(`App Store answered ${response.status}`, 502, "upstream", text.slice(0, 200));
    }
    return { environment, body: JSON.parse(text) };
  }
  throw new StoreError("Achat inconnu de l'App Store.", 404, last ? String(last.status) : "");
}

/// App Store « status » → the state store_settle() keeps.
///   1 active · 2 expired · 3 billing retry (no access) · 4 grace · 5 revoked
export function appleState(status, tx, renewal) {
  if (tx?.revocationDate) return "revoked";
  switch (Number(status)) {
    case 1: return renewal && Number(renewal.autoRenewStatus) === 0 ? "cancelled" : "active";
    case 2: return "expired";
    case 3: return "on_hold";
    case 4: return "grace";
    case 5: return "revoked";
    default: return "expired";
  }
}

/// What store_settle() needs, from Apple's verified transaction + renewal.
export function appleSettlement(tx, renewal, status) {
  const state = appleState(status, tx, renewal);
  // In grace, access runs to the grace period's end, not the paid one.
  const end = state === "grace" && renewal?.gracePeriodExpiresDate
    ? Number(renewal.gracePeriodExpiresDate)
    : Number(tx.expiresDate || 0);
  return {
    platform: "apple",
    productId: tx.productId,
    originalId: String(tx.originalTransactionId || tx.transactionId || ""),
    state,
    expiresAt: end ? new Date(end).toISOString() : null,
    autoRenew: renewal ? Number(renewal.autoRenewStatus) === 1 : false,
    environment: String(tx.environment || "").toLowerCase() === "sandbox" ? "sandbox" : "production",
    orgId: tx.appAccountToken ? String(tx.appAccountToken).toLowerCase() : null,
    // When Apple signed what this says (store_settle ignores older news).
    signedAt: signedAt(tx, renewal),
  };
}

/// The latest signedDate of the JWS behind a settlement, or now.
function signedAt(tx, renewal) {
  const dates = [Number(tx?.signedDate || 0), Number(renewal?.signedDate || 0)].filter((d) => d > 0);
  return new Date(dates.length ? Math.max(...dates) : Date.now()).toISOString();
}

/// Refuses what is not Mara Pro for this app.
export function checkAppleTransaction(env, tx) {
  if (tx.bundleId !== appleBundle(env)) throw new StoreError("Cet achat n'est pas pour Mara.", 422, "bundle");
  if (!APPLE_PRODUCTS.includes(tx.productId)) {
    throw new StoreError("Cet achat n'est pas Mara Pro.", 422, "product");
  }
}

/// The purchase the app reported, as Apple holds it now.
export async function appleLookup(env, transactionId, io = { fetch: callFetch }, verify = {}) {
  if (!/^\d{1,30}$/.test(String(transactionId || ""))) {
    throw new StoreError("Identifiant d'achat App Store invalide.", 400, "transaction");
  }
  const got = await appleGet(env, `/inApps/v1/transactions/${transactionId}`, io);
  const tx = await verifyAppleJws(got.body.signedTransactionInfo, verify);
  checkAppleTransaction(env, tx);
  const statuses = await appleGet(env, `/inApps/v1/subscriptions/${transactionId}`, io);
  let status = null;
  let latest = tx;
  let renewal = null;
  for (const group of statuses.body.data || []) {
    for (const item of group.lastTransactions || []) {
      if (String(item.originalTransactionId) !== String(tx.originalTransactionId)) continue;
      status = item.status;
      if (item.signedTransactionInfo) latest = await verifyAppleJws(item.signedTransactionInfo, verify);
      if (item.signedRenewalInfo) renewal = await verifyAppleJws(item.signedRenewalInfo, verify);
    }
  }
  if (latest !== tx) checkAppleTransaction(env, latest);
  // The org travels in the first purchase's appAccountToken; a renewal
  // carries it too, but the purchase the app reported is the one that
  // proves it.
  const settled = appleSettlement(latest, renewal, status ?? (tx.revocationDate ? 5 : 1));
  settled.orgId = tx.appAccountToken ? String(tx.appAccountToken).toLowerCase() : settled.orgId;
  return { ...settled, raw: { transaction: latest, renewal, status } };
}

/// App Store Server Notifications V2: the decoded, verified notification,
/// or null for one that is not about a subscription of ours. The store
/// door (store.js appleNotify) believes none of its state: it is a
/// wake-up, and Apple's API is asked what holds now (review S1).
export async function appleNotification(env, body, verify = {}) {
  const payload = await verifyAppleJws(body?.signedPayload, verify);
  const data = payload.data || {};
  if (payload.notificationType === "TEST") return { test: true, payload };
  if (data.bundleId && data.bundleId !== appleBundle(env)) {
    throw new StoreError("Cette notification n'est pas pour Mara.", 422, "bundle");
  }
  if (!data.signedTransactionInfo) return { ignored: payload.notificationType || "", payload };
  const tx = await verifyAppleJws(data.signedTransactionInfo, verify);
  checkAppleTransaction(env, tx);
  const renewal = data.signedRenewalInfo ? await verifyAppleJws(data.signedRenewalInfo, verify) : null;
  let status = data.status;
  if (status == null) {
    status = payload.notificationType === "EXPIRED" ? 2
      : payload.notificationType === "REFUND" || payload.notificationType === "REVOKE" ? 5
        : 1;
  }
  return {
    type: payload.notificationType,
    subtype: payload.subtype || null,
    settlement: { ...appleSettlement(tx, renewal, status), raw: { notification: payload.notificationType, transaction: tx, renewal, status } },
  };
}

/// The daily re-check: a subscription by its original transaction id.
export async function appleRecheck(env, originalId, io = { fetch: callFetch }, verify = {}) {
  return appleLookup(env, originalId, io, verify);
}
