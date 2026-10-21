// Mara Pro through the App Store and Google Play: the Worker's doors (130).
//
//   POST /store/verify         the app, with the owner's Supabase token,
//                              right after the store took the payment (or
//                              on « Restaurer mes achats »):
//                              { platform: apple|google, org_id?,
//                                product_id, transaction_id | token }
//                              → { ok, org_id, pro, state, expires_at }
//                              (org_id left out by the app's launch-time
//                              listener: the store's own business is used)
//   POST /store/apple-notify   App Store Server Notifications V2
//   POST /store/google-notify?secret=…   Real-Time Developer
//                              Notifications, by Pub/Sub push
//   cron, daily                every subscription near its end, asked
//                              again (store_due)
//
// The rule, as for Stripe: the app's word is never the proof. The app
// sends only an id; the Worker asks Apple or Google, checks it is Mara
// Pro for bf.kaj.app and that the business the store holds (Apple's
// appAccountToken, Google's obfuscatedExternalAccountId — the org id the
// app passed at purchase) is the one asked for, then store_settle() (the
// service role's alone) writes it down. Who may ask is Postgres's answer,
// as the caller: store_verify_begin() — an administrator of the business.
//
// Refusals carry a code the app translates and acts on (review S3):
// definitive — wrong_org, no_org, replayed, product, bundle, base_plan,
// transaction, token, sandbox: the app finishes the purchase and says
// why; passing — session (401), not_admin (403), config (503), anything
// 5xx: the app leaves the purchase open for the store to hand back.

import {
  StoreError, appleConfigured, appleLookup, appleNotification,
} from "./apple.js";
import {
  googleAcknowledge, googleConfigured, googleLookup, googleNotification,
} from "./google.js";
import { sameSecret } from "./jwt.js";
import { googleSpotPurchased, spotRefund } from "./spots.js";
import { SignatureError } from "./x509.js";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ENTITLED = new Set(["active", "grace", "cancelled"]);

/// The store's answer, for the purchase the app reported.
async function lookup(platform, body, env, io) {
  if (platform === "apple") {
    if (!appleConfigured(env)) throw new StoreError("L'App Store n'est pas encore relié à Marakaj.", 503, "config");
    // The app's signed transaction (StoreKit 2's JWS), when sent, names
    // the host to ask; Apple's API is still what is believed.
    return appleLookup(env, body?.transaction_id, io, io.verify,
      { signed: typeof body?.signed_transaction === "string" ? body.signed_transaction : null });
  }
  if (!googleConfigured(env)) throw new StoreError("Google Play n'est pas encore relié à Marakaj.", 503, "config");
  return googleLookup(env, body?.token, io);
}

async function settle(settlement, orgId, env, io, boughtBy = null) {
  const result = await io.rpcService(env, "store_settle", {
    p_platform: settlement.platform,
    p_org_id: orgId,
    p_product_id: settlement.productId,
    p_original_id: settlement.originalId,
    p_state: settlement.state,
    p_expires_at: settlement.expiresAt,
    p_auto_renew: settlement.autoRenew,
    p_environment: settlement.environment,
    p_raw: settlement.raw ?? null,
    p_bought_by: boughtBy,
    p_replaces: settlement.replaces ?? null,
    p_signed_at: settlement.signedAt ?? null,
  }, io.fetch);
  if (!result?.ok) {
    if (result?.reason === "another business") {
      throw new StoreError("Cet abonnement est déjà celui d'une autre entreprise.", 409, "replayed");
    }
    if (result?.reason === "sandbox") {
      // 128 5c: a test purchase counts only for Mara's own businesses and
      // the App Review account's (platform setting store_review_account).
      throw new StoreError("Achat de test refusé : un achat fait avec un compte de test (sandbox, TestFlight) n'active Marakaj Pro que pour les comptes de test de Marakaj.", 403, "sandbox");
    }
    if (result?.reason === "no such business") {
      throw new StoreError("Cette entreprise n'existe plus sur Marakaj.", 404, "no_business");
    }
    throw new StoreError("L'abonnement n'a pas pu être enregistré.", 502, result?.reason || "");
  }
  return result;
}

/// What a notification door does with a refusal that no retry will
/// change (review S7): answered 200 « ignored » — Apple and Pub/Sub retry
/// anything else for days — and logged, never with a token.
const SETTLED_NEVER = new Set(["no_business", "replayed", "sandbox", "wrong_org", "no_org",
  "product", "bundle", "base_plan", "transaction", "token"]);
function ignoredNotice(door, error, platform) {
  if (error instanceof StoreError && (SETTLED_NEVER.has(error.code) || error.status === 404)) {
    console.warn(`store ${door}: ignored (${error.code || error.status})`, platform);
    return { ignored: error.code || String(error.status) };
  }
  return null;
}

/// Postgres's refusal of a verification, as the app can act on it.
function beginRefused(error) {
  if (error?.upstream === 401) {
    return new StoreError("Votre session a expiré : reconnectez-vous.", 401, "session");
  }
  if (error?.status === 400) {
    return new StoreError(error.message || "Seul un administrateur abonne l'entreprise à Marakaj Pro", 403, "not_admin");
  }
  return error;
}

/// The owner's app, after a purchase or a restore — or, since review S3,
/// the app's purchase listener at launch, which may not know the
/// business: then org_id is left out and the business is the one the
/// store holds (Apple's appAccountToken, Google's
/// obfuscatedExternalAccountId), the caller still having to administer it.
export async function storeVerify(body, userToken, env, io) {
  const platform = body?.platform;
  if (platform !== "apple" && platform !== "google") {
    throw new StoreError("Boutique inconnue.", 400, "platform");
  }
  const named = body?.org_id == null || body.org_id === "" ? null : String(body.org_id).toLowerCase();
  if (named !== null && !UUID.test(named)) throw new StoreError("Entreprise inconnue.", 400, "org");
  const begin = async (orgId) => {
    try {
      return await io.rpcAs(env, userToken, "store_verify_begin", { p_org_id: orgId }, io.fetch);
    } catch (error) {
      throw beginRefused(error);
    }
  };
  // Postgres, as the caller: an administrator of this business, or 4xx —
  // before the store is asked anything when the business is named.
  let begun = named ? await begin(named) : null;

  const settlement = await lookup(platform, body, env, io);
  if (body?.product_id && platform === "apple" && body.product_id !== settlement.productId
      && body.product_id !== settlement.raw?.transaction?.productId) {
    throw new StoreError("Cet achat n'est pas celui annoncé.", 422, "product");
  }
  if (!settlement.orgId || !UUID.test(settlement.orgId)) {
    throw new StoreError("Cet achat ne dit pas pour quelle entreprise il a été fait.", 409, "no_org");
  }
  if (named && settlement.orgId !== named) {
    throw new StoreError("Cet achat a été fait pour une autre entreprise.", 409, "wrong_org");
  }
  const orgId = settlement.orgId;
  if (!begun) begun = await begin(orgId);
  const result = await settle(settlement, orgId, env, io, begun?.user_id || null);
  if (platform === "google" && !settlement.acknowledged && settlement.state !== "pending"
      && settlement.state !== "expired") {
    await googleAcknowledge(env, settlement.originalId, io);
  }
  return {
    ok: true,
    org_id: orgId,
    pro: Boolean(result.pro),
    state: result.stale ? (result.state || settlement.state) : settlement.state,
    expires_at: result.stale ? (result.expires_at || settlement.expiresAt) : settlement.expiresAt,
    entitled: ENTITLED.has(settlement.state),
  };
}

/// App Store Server Notifications V2. The notification is a wake-up only
/// (review S1): its signature is checked — so nobody else makes Mara ask
/// Apple — and then the subscription is read again from the App Store
/// Server API, and what Apple says NOW is settled, with Apple's own
/// signedDate, so a notification retried or arriving late never undoes a
/// refund. Its payload's state is never written.
export async function appleNotify(body, env, io) {
  const note = await appleNotification(env, body, io.verify);
  if (note.test) return { test: true };
  // A spot's payment refunded by Apple (139): written, and the spot ends.
  if (note.spotRefund) {
    return spotRefund(env, io, "apple", note.spotRefund.transactionId, note.spotRefund.reason);
  }
  if (!note.settlement) return { ignored: note.ignored || "" };
  if (!appleConfigured(env)) throw new StoreError("L'App Store n'est pas encore relié à Marakaj.", 503, "config");
  let s;
  try {
    // The verified notification says which host holds it.
    s = await appleLookup(env, note.settlement.originalId, io, io.verify,
      { environment: note.environment ?? null });
  } catch (error) {
    const ignored = ignoredNotice("apple-notify", error, "apple");
    if (ignored) return ignored;
    throw error;
  }
  s.raw = { ...(s.raw || {}), notification: note.type, subtype: note.subtype };
  const orgId = s.orgId && UUID.test(s.orgId)
    ? s.orgId
    : await io.rpcService(env, "store_org_of", { p_platform: "apple", p_original_id: s.originalId }, io.fetch);
  if (!orgId) {
    console.warn("store apple-notify: ignored (no business on the subscription)");
    return { ignored: "no business on the subscription" };
  }
  try {
    const result = await settle(s, orgId, env, io);
    return { settled: true, pro: Boolean(result.pro), state: result.stale ? result.state : s.state,
      stale: Boolean(result.stale), type: note.type };
  } catch (error) {
    const ignored = ignoredNotice("apple-notify", error, "apple");
    if (ignored) return ignored;
    throw error;
  }
}

/// Google's Real-Time Developer Notifications (Pub/Sub push). The URL
/// carries GOOGLE_NOTIFY_SECRET, which only the owner's Pub/Sub
/// subscription knows.
export async function googleNotify(url, body, env, io) {
  if (!env.GOOGLE_NOTIFY_SECRET || !sameSecret(url.searchParams.get("secret"), env.GOOGLE_NOTIFY_SECRET)) {
    throw new StoreError("bad secret", 401, "secret");
  }
  const note = googleNotification(body);
  if (!note || note.test || note.foreign || note.ignored) return { ignored: true, test: Boolean(note?.test) };
  // A one-time purchase voided (139: a spot refunded, charged back): the
  // push is the owner's Pub/Sub with the secret; the database knows
  // whether the token is a spot's, and ends it once.
  // A spot bought (139), heard without the app: verified and programmed.
  if (note.oneTime) {
    if (!googleConfigured(env)) throw new StoreError("Google Play n'est pas encore relié à Marakaj.", 503, "config");
    try {
      return await googleSpotPurchased(env, note.oneTime, io);
    } catch (error) {
      if (error instanceof StoreError && error.status < 500) return { ignored: error.code || true };
      throw error;
    }
  }
  if (note.voided) {
    return spotRefund(env, io, "google", note.voided.token,
      `google voided${note.voided.refundType != null ? ` (${note.voided.refundType})` : ""}`);
  }
  if (!googleConfigured(env)) throw new StoreError("Google Play n'est pas encore relié à Marakaj.", 503, "config");
  let s;
  try {
    s = await googleLookup(env, note.token, io);
  } catch (error) {
    // A token Google no longer knows, or another product's: nothing to
    // retry (Pub/Sub retries anything but a 2xx).
    const ignored = ignoredNotice("google-notify", error, "google");
    if (ignored) return ignored;
    if (error instanceof StoreError && error.status < 500) return { ignored: error.code || true };
    throw error;
  }
  const orgId = s.orgId && UUID.test(s.orgId)
    ? s.orgId
    : await io.rpcService(env, "store_org_of", { p_platform: "google", p_original_id: s.originalId }, io.fetch);
  if (!orgId) {
    console.warn("store google-notify: ignored (no business on the subscription)");
    return { ignored: "no business on the subscription" };
  }
  let result;
  try {
    result = await settle(s, orgId, env, io);
  } catch (error) {
    const ignored = ignoredNotice("google-notify", error, "google");
    if (ignored) return ignored;
    throw error;
  }
  // A purchase whose app died before /store/verify: acknowledged here, so
  // Google does not refund what the business now has.
  if (!s.acknowledged && ENTITLED.has(s.state)) await googleAcknowledge(env, s.originalId, io);
  return { settled: true, pro: Boolean(result.pro), state: s.state, type: note.type };
}

/// The daily re-check of what is near its end (store_due). A failure is
/// counted and logged by its code — never a token — so a dead key shows
/// in the Worker's logs.
export async function storeRecheck(env, io) {
  const due = (await io.rpcService(env, "store_due", {}, io.fetch)) || [];
  let checked = 0;
  let failed = 0;
  for (const row of due) {
    try {
      let s;
      if (row.platform === "apple") {
        if (!appleConfigured(env)) continue;
        s = await appleLookup(env, row.original_id, io, io.verify, { environment: row.environment });
      } else {
        if (!googleConfigured(env)) continue;
        s = await googleLookup(env, row.original_id, io);
      }
      await settle(s, row.org_id, env, io);
      checked++;
    } catch (error) {
      if (error instanceof StoreError && error.status === 404) {
        // The store no longer knows it: over.
        await settle({
          platform: row.platform, productId: row.product_id, originalId: row.original_id,
          state: "expired", expiresAt: row.expires_at, autoRenew: false,
          environment: row.environment || "production", raw: { recheck: "unknown to the store" },
          signedAt: new Date(io.now?.() ?? Date.now()).toISOString(),
        }, row.org_id, env, io).catch(() => {});
        checked++;
      } else {
        failed++;
        console.error("store recheck failed", row.platform,
          error instanceof StoreError ? `${error.status} ${error.code} ${error.detail || ""}`.trim() : String(error?.name || "error"));
      }
    }
  }
  return { due: due.length, checked, failed };
}

/// An error, as the door answers it.
export function storeProblem(error) {
  if (error instanceof SignatureError) return { status: 401, body: { error: "bad signature" } };
  if (error instanceof StoreError) {
    return { status: error.status || 400, body: { error: error.message, code: error.code || undefined } };
  }
  return {
    status: error?.status && error.status < 500 ? error.status : 502,
    body: { error: error?.message || "La vérification a échoué." },
  };
}
