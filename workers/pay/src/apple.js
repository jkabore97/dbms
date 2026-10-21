// Mara Pro bought in the iPhone app: what Apple says about it (130).
//
// The App Store Server API, signed with an In-App Purchase key (ES256 JWT:
// APPLE_IAP_KEY_ID, APPLE_IAP_ISSUER_ID, APPLE_IAP_PRIVATE_KEY — the .p8's
// text — for the bundle APPLE_BUNDLE_ID, bf.kaj.app by default):
//
//   GET /inApps/v1/transactions/{id}    the purchase the app reported
//   GET /inApps/v1/subscriptions/{id}   where its subscription stands now
//
// The host the purchase names when known (the app's signed transaction, a
// notification, the row), else production first, then the sandbox
// (TestFlight, App Review) when production says « not here » — a 404, or
// the 401 production answers an app never released (appleGet). Every answer is a JWS, checked
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
/// The two consumable spots (139), never Mara Pro.
export const APPLE_SPOT_PRODUCT_IDS = ["bf.kaj.app.spot.article7", "bf.kaj.app.spot.shop7"];
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

/// Apple's own error code in a refusal's body ({"errorCode":4040010,…}),
/// or "" — for the Worker's log, never the app's answer.
function appleErrorCode(text) {
  try {
    const code = JSON.parse(text)?.errorCode;
    return code == null ? "" : String(code);
  } catch {
    return "";
  }
}

/// « production » / « sandbox » from what Apple writes (« Production »,
/// « Sandbox »), or null for anything else (Xcode's local StoreKit tests,
/// a row that never said).
export function appleEnvironment(value) {
  const e = String(value || "").toLowerCase();
  return e === "production" || e === "sandbox" ? e : null;
}

/// One App Store Server API call (exported for the spots, 139:
/// src/spots.js). With [environment] known — a verified signed
/// transaction, a notification, a row written before — that host alone is
/// asked. Otherwise production first, then the sandbox when production
/// answers « not here »:
///
///   404  (4040010 TransactionIdNotFound) — a sandbox (TestFlight, App
///        Review) purchase, for an app already on the App Store;
///   401  — production's answer to EVERY call, with a right key, while the
///        app has never been released on the App Store (Apple staff on the
///        developer forums: production access opens with the first
///        release). Marakaj's iPhone app is in TestFlight only: until the
///        sandbox was asked after a 401, no Apple purchase could ever be
///        verified (the app said « Le paiement est fait, mais Marakaj n'a
///        pas encore pu le vérifier… » at every launch).
///
/// A key that is really wrong is then refused by the sandbox too (401) and
/// said so: every host's status and Apple's error code go to the Worker's
/// log (StoreError.detail) — never the bearer, never the transaction id.
export async function appleGet(env, path, io, { environment = null } = {}) {
  const token = await appleToken(env, io.now?.());
  const order = environment && HOSTS[environment] ? [environment] : ["production", "sandbox"];
  const misses = [];
  for (const host of order) {
    const response = await io.fetch(`${HOSTS[host]}${path}`, {
      method: "GET",
      headers: { Authorization: `Bearer ${token}` },
    });
    const text = await response.text();
    if (response.ok) return { environment: host, body: JSON.parse(text) };
    const code = appleErrorCode(text);
    misses.push(`${host} ${response.status}${code ? ` ${code}` : ""}`);
    const notHere = response.status === 404 || response.status === 401;
    if (host === "production" && order.length > 1 && notHere) continue;
    const detail = `${misses.join(", ")}${text ? ` · ${text.slice(0, 200)}` : ""}`;
    if (response.status === 404) throw new StoreError("Achat inconnu de l'App Store.", 404, "unknown", detail);
    throw new StoreError(`App Store answered ${response.status}`, 502, "upstream", detail);
  }
  throw new StoreError("App Store answered nothing", 502, "upstream", misses.join(", "));
}

/// The environment a signed transaction the app sent (StoreKit 2's
/// jwsRepresentation) names, once Apple's signature on it holds and it is
/// the transaction asked about — or null, and both hosts are asked. Only a
/// hint of which host to ask: what is settled is what Apple's API answers,
/// never this.
export async function appleHintedEnvironment(env, transactionId, signed, verify = {}) {
  if (!signed) return null;
  try {
    const tx = await verifyAppleJws(signed, verify);
    if (String(tx.transactionId) !== String(transactionId) || tx.bundleId !== appleBundle(env)) return null;
    return appleEnvironment(tx.environment);
  } catch {
    return null;
  }
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
  if (tx.bundleId !== appleBundle(env)) throw new StoreError("Cet achat n'est pas pour Marakaj.", 422, "bundle");
  if (!APPLE_PRODUCTS.includes(tx.productId)) {
    throw new StoreError("Cet achat n'est pas Marakaj Pro.", 422, "product");
  }
}

/// The purchase the app reported, as Apple holds it now.
///
/// [hint]: { environment } when it is already known (a notification's, a
/// row's), or { signed } — the signed transaction the app sent — whose
/// verified environment picks the host.
export async function appleLookup(env, transactionId, io = { fetch: callFetch }, verify = {}, hint = {}) {
  if (!/^\d{1,30}$/.test(String(transactionId || ""))) {
    throw new StoreError("Identifiant d'achat App Store invalide.", 400, "transaction");
  }
  const environment = appleEnvironment(hint.environment)
    ?? await appleHintedEnvironment(env, transactionId, hint.signed, verify);
  const got = await appleGet(env, `/inApps/v1/transactions/${transactionId}`, io, { environment });
  const tx = await verifyAppleJws(got.body.signedTransactionInfo, verify);
  checkAppleTransaction(env, tx);
  // Where the transaction was found is where its subscription is.
  const statuses = await appleGet(env, `/inApps/v1/subscriptions/${transactionId}`, io,
    { environment: got.environment });
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
    throw new StoreError("Cette notification n'est pas pour Marakaj.", 422, "bundle");
  }
  if (!data.signedTransactionInfo) return { ignored: payload.notificationType || "", payload };
  const tx = await verifyAppleJws(data.signedTransactionInfo, verify);
  // A spot (139) is a consumable, not Mara Pro: its notifications change
  // no subscription — a spot is programmed by /store/spot-verify alone.
  // A REFUND (or REVOKE) of one, signed by Apple and carrying the
  // transaction's revocationDate, is handed to the store door as
  // spotRefund: the payment is written refunded and its spot ends
  // (spot_refund). Anything else about a spot (CONSUMPTION_REQUEST…) is
  // answered 200 and changes nothing.
  if (tx.bundleId === appleBundle(env) && APPLE_SPOT_PRODUCT_IDS.includes(tx.productId)) {
    const type = payload.notificationType || "";
    if ((type === "REFUND" || type === "REVOKE") && tx.revocationDate && tx.transactionId) {
      return {
        ignored: `spot ${type}`,
        spotRefund: { transactionId: String(tx.transactionId), reason: `apple ${type}` },
        payload,
      };
    }
    return { ignored: `spot ${type}`.trim(), payload };
  }
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
    // Which host holds it (« Sandbox » / « Production »), signed by Apple.
    environment: appleEnvironment(data.environment) ?? appleEnvironment(tx.environment),
    settlement: { ...appleSettlement(tx, renewal, status), raw: { notification: payload.notificationType, transaction: tx, renewal, status } },
  };
}

/// The daily re-check: a subscription by its original transaction id.
export async function appleRecheck(env, originalId, io = { fetch: callFetch }, verify = {}, environment = null) {
  return appleLookup(env, originalId, io, verify, { environment });
}
