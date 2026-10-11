// Mara Pro through the App Store and Google Play: the Worker's doors (130).
//
//   POST /store/verify         the app, with the owner's Supabase token,
//                              right after the store took the payment (or
//                              on « Restaurer mes achats »):
//                              { platform: apple|google, org_id,
//                                product_id, transaction_id | token }
//                              → { ok, pro, state, expires_at }
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

import {
  StoreError, appleConfigured, appleLookup, appleNotification,
} from "./apple.js";
import {
  googleAcknowledge, googleConfigured, googleLookup, googleNotification,
} from "./google.js";
import { sameSecret } from "./jwt.js";
import { SignatureError } from "./x509.js";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ENTITLED = new Set(["active", "grace", "cancelled"]);

/// The store's answer, for the purchase the app reported.
async function lookup(platform, body, env, io) {
  if (platform === "apple") {
    if (!appleConfigured(env)) throw new StoreError("L'App Store n'est pas encore relié à Mara.", 503, "config");
    return appleLookup(env, body?.transaction_id, io, io.verify);
  }
  if (!googleConfigured(env)) throw new StoreError("Google Play n'est pas encore relié à Mara.", 503, "config");
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
  }, io.fetch);
  if (!result?.ok) {
    if (result?.reason === "another business") {
      throw new StoreError("Cet abonnement est déjà celui d'une autre entreprise.", 409, "replayed");
    }
    throw new StoreError("L'abonnement n'a pas pu être enregistré.", 502, result?.reason || "");
  }
  return result;
}

/// The owner's app, after a purchase or a restore.
export async function storeVerify(body, userToken, env, io) {
  const platform = body?.platform;
  if (platform !== "apple" && platform !== "google") {
    throw new StoreError("Boutique inconnue.", 400, "platform");
  }
  const orgId = String(body?.org_id || "").toLowerCase();
  if (!UUID.test(orgId)) throw new StoreError("Entreprise inconnue.", 400, "org");
  // Postgres, as the caller: an administrator of this business, or 4xx.
  const begun = await io.rpcAs(env, userToken, "store_verify_begin", { p_org_id: orgId }, io.fetch);

  const settlement = await lookup(platform, body, env, io);
  if (body?.product_id && platform === "apple" && body.product_id !== settlement.productId
      && body.product_id !== settlement.raw?.transaction?.productId) {
    throw new StoreError("Cet achat n'est pas celui annoncé.", 422, "product");
  }
  if (!settlement.orgId) {
    throw new StoreError("Cet achat ne dit pas pour quelle entreprise il a été fait.", 409, "no_org");
  }
  if (settlement.orgId !== orgId) {
    throw new StoreError("Cet achat a été fait pour une autre entreprise.", 409, "wrong_org");
  }
  const result = await settle(settlement, orgId, env, io, begun?.user_id || null);
  if (platform === "google" && !settlement.acknowledged && settlement.state !== "pending"
      && settlement.state !== "expired") {
    await googleAcknowledge(env, settlement.originalId, io);
  }
  return {
    ok: true,
    pro: Boolean(result.pro),
    state: settlement.state,
    expires_at: settlement.expiresAt,
    entitled: ENTITLED.has(settlement.state),
  };
}

/// App Store Server Notifications V2.
export async function appleNotify(body, env, io) {
  const note = await appleNotification(env, body, io.verify);
  if (note.test) return { test: true };
  if (!note.settlement) return { ignored: note.ignored || "" };
  const s = note.settlement;
  const orgId = s.orgId && UUID.test(s.orgId)
    ? s.orgId
    : await io.rpcService(env, "store_org_of", { p_platform: "apple", p_original_id: s.originalId }, io.fetch);
  if (!orgId) return { ignored: "no business on the subscription" };
  const result = await settle(s, orgId, env, io);
  return { settled: true, pro: Boolean(result.pro), state: s.state, type: note.type };
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
  if (!googleConfigured(env)) throw new StoreError("Google Play n'est pas encore relié à Mara.", 503, "config");
  let s;
  try {
    s = await googleLookup(env, note.token, io);
  } catch (error) {
    // A token Google no longer knows, or another product's: nothing to
    // retry (Pub/Sub retries anything but a 2xx).
    if (error instanceof StoreError && error.status < 500) return { ignored: error.code || true };
    throw error;
  }
  const orgId = s.orgId && UUID.test(s.orgId)
    ? s.orgId
    : await io.rpcService(env, "store_org_of", { p_platform: "google", p_original_id: s.originalId }, io.fetch);
  if (!orgId) return { ignored: "no business on the subscription" };
  const result = await settle(s, orgId, env, io);
  // A purchase whose app died before /store/verify: acknowledged here, so
  // Google does not refund what the business now has.
  if (!s.acknowledged && ENTITLED.has(s.state)) await googleAcknowledge(env, s.originalId, io);
  return { settled: true, pro: Boolean(result.pro), state: s.state, type: note.type };
}

/// The daily re-check of what is near its end (store_due).
export async function storeRecheck(env, io) {
  const due = (await io.rpcService(env, "store_due", {}, io.fetch)) || [];
  let checked = 0;
  let failed = 0;
  for (const row of due) {
    try {
      let s;
      if (row.platform === "apple") {
        if (!appleConfigured(env)) continue;
        s = await appleLookup(env, row.original_id, io, io.verify);
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
        }, row.org_id, env, io).catch(() => {});
        checked++;
      } else {
        failed++;
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
