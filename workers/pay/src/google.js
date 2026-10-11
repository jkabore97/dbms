// Mara Pro bought in the Android app: what Google Play says about it (130).
//
// The Google Play Developer API (androidpublisher v3) with the service
// account in PLAY_SERVICE_ACCOUNT_JSON — the same GitHub secret that
// publishes the app to Play (build.yml), now also a Worker secret
// (deploy-pay.yml, deploy-account-admin.yml). The account needs, in Play
// Console › Users and permissions, « View financial data » and « Manage
// orders and subscriptions » for bf.kaj.app.
//
//   GET  purchases/subscriptionsv2/tokens/{token}           where it stands
//   POST purchases/subscriptions/mara_pro/tokens/{t}:acknowledge
//        within three days, or Google refunds it
//   POST purchases/subscriptionsv2/tokens/{token}:revoke     (account
//        deletion: the business is gone, the rest of the period refunded)
//
// And Real-Time Developer Notifications (POST /store/google-notify): a
// Pub/Sub push whose message names a token — the token is read again from
// Google, never the message believed.

import { signRs256 } from "./jwt.js";
import { StoreError } from "./apple.js";

export const GOOGLE_PACKAGE = "bf.kaj.app";
export const GOOGLE_PRODUCT = "mara_pro";
export const GOOGLE_BASE_PLANS = ["monthly", "yearly"];
const API = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications";

export function googleConfigured(env) {
  return Boolean(env.PLAY_SERVICE_ACCOUNT_JSON);
}

function serviceAccount(env) {
  try {
    const sa = JSON.parse(env.PLAY_SERVICE_ACCOUNT_JSON);
    if (!sa.client_email || !sa.private_key) throw new Error("incomplete");
    return sa;
  } catch {
    throw new StoreError("Google Play n'est pas configuré.", 503, "service_account");
  }
}

/// An access token for the Play Developer API (one hour; asked per call —
/// a verification is rare enough).
export async function googleToken(env, io = { fetch }) {
  const sa = serviceAccount(env);
  const iat = Math.floor((io.now?.() ?? Date.now()) / 1000);
  const tokenUri = sa.token_uri || "https://oauth2.googleapis.com/token";
  const assertion = await signRs256({ kid: sa.private_key_id }, {
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/androidpublisher",
    aud: tokenUri,
    iat,
    exp: iat + 3600,
  }, sa.private_key);
  const response = await io.fetch(tokenUri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }).toString(),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok || !data.access_token) {
    throw new StoreError("Google a refusé la connexion du serveur.", 502, String(response.status));
  }
  return data.access_token;
}

async function play(env, method, path, io, body) {
  const token = await googleToken(env, io);
  const response = await io.fetch(`${API}/${GOOGLE_PACKAGE}/${path}`, {
    method,
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await response.text();
  if (response.status === 404 || response.status === 410) {
    throw new StoreError("Achat inconnu de Google Play.", 404, String(response.status));
  }
  if (!response.ok) throw new StoreError(`Google Play answered ${response.status}`, 502, text.slice(0, 200));
  return text ? JSON.parse(text) : {};
}

const STATES = {
  SUBSCRIPTION_STATE_ACTIVE: "active",
  SUBSCRIPTION_STATE_IN_GRACE_PERIOD: "grace",
  SUBSCRIPTION_STATE_ON_HOLD: "on_hold",
  SUBSCRIPTION_STATE_PAUSED: "paused",
  SUBSCRIPTION_STATE_CANCELED: "cancelled",
  SUBSCRIPTION_STATE_EXPIRED: "expired",
  SUBSCRIPTION_STATE_PENDING: "pending",
  SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED: "expired",
};

export function googleState(state) {
  return STATES[state] || "expired";
}

/// What store_settle() needs, from a SubscriptionPurchaseV2.
export function googleSettlement(token, sub) {
  const items = (sub.lineItems || []).filter((l) => l.productId === GOOGLE_PRODUCT);
  if (!items.length) throw new StoreError("Cet achat n'est pas Mara Pro.", 422, "product");
  const latest = items.reduce((a, b) =>
    (Date.parse(b.expiryTime || 0) > Date.parse(a.expiryTime || 0) ? b : a));
  const basePlan = latest.offerDetails?.basePlanId || null;
  // Mara Pro is sold as one of its two base plans, and only so: a line
  // with none (or another) is not a purchase of ours.
  if (!basePlan || !GOOGLE_BASE_PLANS.includes(basePlan)) {
    throw new StoreError("Cet achat n'est pas Mara Pro.", 422, "base_plan");
  }
  return {
    platform: "google",
    productId: `${GOOGLE_PRODUCT}:${basePlan}`,
    originalId: token,
    state: googleState(sub.subscriptionState),
    expiresAt: latest.expiryTime ? new Date(latest.expiryTime).toISOString() : null,
    autoRenew: Boolean(latest.autoRenewingPlan?.autoRenewEnabled),
    environment: sub.testPurchase ? "sandbox" : "production",
    orgId: sub.externalAccountIdentifiers?.obfuscatedExternalAccountId
      ? String(sub.externalAccountIdentifiers.obfuscatedExternalAccountId).toLowerCase()
      : null,
    replaces: sub.linkedPurchaseToken || null,
    acknowledged: sub.acknowledgementState === "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
    raw: sub,
  };
}

function checkToken(token) {
  if (!/^[A-Za-z0-9._\-:]{10,4096}$/.test(String(token || ""))) {
    throw new StoreError("Jeton d'achat Google Play invalide.", 400, "token");
  }
}

export async function googleLookup(env, token, io = { fetch }) {
  checkToken(token);
  const sub = await play(env, "GET", `purchases/subscriptionsv2/tokens/${encodeURIComponent(token)}`, io);
  const settlement = googleSettlement(token, sub);
  // Play's answer is as of the moment it was read: that is when « the
  // store said so » (store_settle ignores anything older). A Pub/Sub
  // eventTime is never used for it — the notification is only a wake-up.
  settlement.signedAt = new Date(io.now?.() ?? Date.now()).toISOString();
  return settlement;
}

/// Google refunds a purchase not acknowledged within three days.
export async function googleAcknowledge(env, token, io = { fetch }) {
  checkToken(token);
  await play(env, "POST",
    `purchases/subscriptions/${GOOGLE_PRODUCT}/tokens/${encodeURIComponent(token)}:acknowledge`, io, {});
}

/// Ends a subscription now and refunds what is left of the period (the
/// business it paid for was deleted with its owner's account).
export async function googleRevoke(env, token, io = { fetch }) {
  checkToken(token);
  await play(env, "POST", `purchases/subscriptionsv2/tokens/${encodeURIComponent(token)}:revoke`, io, {
    revocationContext: { proratedRefund: {} },
  });
}

/// A Pub/Sub push: its RTDN, decoded, or null for anything else.
export function googleNotification(body) {
  const data = body?.message?.data;
  if (!data) return null;
  let decoded;
  try {
    decoded = JSON.parse(atob(String(data)));
  } catch {
    return null;
  }
  if (decoded.packageName && decoded.packageName !== GOOGLE_PACKAGE) return { foreign: true };
  if (decoded.testNotification) return { test: true };
  const sn = decoded.subscriptionNotification;
  if (!sn?.purchaseToken) return { ignored: true };
  return {
    type: Number(sn.notificationType),
    token: sn.purchaseToken,
    subscriptionId: sn.subscriptionId || null,
  };
}
