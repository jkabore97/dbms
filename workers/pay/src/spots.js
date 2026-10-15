// « Mettre en avant » paid in the store apps and by card (139, batch 142).
//
//   POST /store/spot-verify   the app, with the owner's Supabase token,
//                             right after Google Play or the App Store
//                             took the payment (or on « Vérifier un achat
//                             déjà payé »):
//                             { platform: apple|google, promotion_id?,
//                               product_id, transaction_id | token }
//                             (a price the app sends is never read)
//                             → { ok, promotion_id, org_id, granted,
//                                 starts_at, ends_at }
//   POST /v1/stripe/spot      the website, with the owner's token:
//                             { promotion_id } → { url } of a one-time
//                             Stripe Checkout Session
//   Stripe's webhook          checkout.session.completed (and
//                             async_payment_succeeded) of a session whose
//                             metadata says kind = spot: read again from
//                             Stripe, and programmed once;
//                             charge.refunded / charge.dispute.created of
//                             a spot's PaymentIntent: read again from
//                             Stripe, and the spot ends (spot_refund).
//   Apple's REFUND / REVOKE   (store.js appleNotify, signed by Apple) and
//   Google's voided purchase  (store.js googleNotify, Pub/Sub with the
//                             secret): the spot's payment is written
//                             refunded and the spot ends, once.
//
// The rule, as for Mara Pro (130): the app's word is never the proof. The
// app sends an id; the Worker asks the store — the Play Developer API's
// purchases.products for Google, the App Store Server API's signed
// transaction for Apple — checks it is one of the two spots of bf.kaj.app,
// that it is paid, which spot it was bought for (the promotion's id rides
// inside the purchase: Google's obfuscatedExternalProfileId beside the
// business in obfuscatedExternalAccountId; Apple's appAccountToken), and
// that the caller administers that spot's business (spot_verify_begin, as
// the caller). Then spot_settle() — the service role's alone — programs
// the spot, once per payment: Google's token, Apple's transaction id and
// Stripe's session are unique per channel, so a payment shown again is
// the spot it already bought, and one shown for another spot is refused.
// Google's purchase is then acknowledged and consumed, so it can be
// bought again next week; Apple's is finished by the app.
//
// The products, as the owner creates them in the stores:
//   Google Play, one-time consumable products: mara_spot_article_7,
//                                             mara_spot_shop_7
//   App Store, Consumable in-app purchases:    bf.kaj.app.spot.article7,
//                                             bf.kaj.app.spot.shop7
//
// Refusals carry a code the app acts on: for good — wrong_spot, no_spot,
// replayed, product, bundle, transaction, token, sandbox, cancelled,
// revoked (the app finishes Apple's transaction; Google's, never
// acknowledged, is refunded by Google after three days); passing —
// session (401), not_admin (403), pending (202), config (503), 5xx.

import { StoreError, appleBundle, appleConfigured, appleGet } from "./apple.js";
import { googleConfigured, googlePlay } from "./google.js";
import {
  createPaymentCheckout, getCheckoutSession, getPaymentIntent, priceLabel, refundPaymentIntent,
} from "./stripe.js";
import { verifyAppleJws } from "./x509.js";

export const GOOGLE_SPOT_PRODUCTS = { mara_spot_article_7: "article", mara_spot_shop_7: "shop" };
export const APPLE_SPOT_PRODUCTS = { "bf.kaj.app.spot.article7": "article", "bf.kaj.app.spot.shop7": "shop" };

export const isSpotProduct = (id) =>
  Object.hasOwn(GOOGLE_SPOT_PRODUCTS, id) || Object.hasOwn(APPLE_SPOT_PRODUCTS, id);

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const uuidOr = (v) => (v && UUID.test(String(v)) ? String(v).toLowerCase() : null);

// ------------------------------------------------------------
// Google Play: purchases.products
// ------------------------------------------------------------

function checkGoogleToken(token) {
  if (!/^[A-Za-z0-9._\-:]{10,4096}$/.test(String(token || ""))) {
    throw new StoreError("Jeton d'achat Google Play invalide.", 400, "token");
  }
}

/// What Google Play says of a spot bought in the Android app.
///   purchaseState     0 purchased · 1 cancelled · 2 pending
///   consumptionState  0 to consume · 1 consumed
///   purchaseType      0 test (licence tester) · 1 promo · 2 rewarded · absent: paid
export async function googleSpotLookup(env, productId, token, io) {
  if (!Object.hasOwn(GOOGLE_SPOT_PRODUCTS, productId)) {
    throw new StoreError("Cet achat n'est pas une mise en avant.", 422, "product");
  }
  checkGoogleToken(token);
  const p = await googlePlay(env, "GET",
    `purchases/products/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(token)}`, io);
  const state = Number(p.purchaseState ?? 0) === 0 ? "purchased"
    : Number(p.purchaseState) === 2 ? "pending" : "cancelled";
  return {
    platform: "google",
    productId,
    kind: GOOGLE_SPOT_PRODUCTS[productId],
    externalId: token,
    state,
    promotionId: uuidOr(p.obfuscatedExternalProfileId),
    orgId: uuidOr(p.obfuscatedExternalAccountId),
    environment: p.purchaseType != null && Number(p.purchaseType) === 0 ? "sandbox" : "production",
    acknowledged: Number(p.acknowledgementState ?? 0) === 1,
    consumed: Number(p.consumptionState ?? 0) === 1,
    orderId: p.orderId || null,
    raw: { orderId: p.orderId || null, regionCode: p.regionCode || null,
      purchaseTimeMillis: p.purchaseTimeMillis || null, purchaseType: p.purchaseType ?? null },
  };
}

/// What the buyer paid, when the Play Developer API's orders say it
/// (orders.get, « View financial data »). Best effort: Google's purchase
/// itself carries no price, so without it the app's own price is kept.
export async function googleOrderTotal(env, orderId, io) {
  if (!orderId || !/^[A-Za-z0-9._\-]{4,200}$/.test(orderId)) return null;
  try {
    const order = await googlePlay(env, "GET", `orders/${encodeURIComponent(orderId)}`, io);
    const total = order?.total;
    if (!total?.currencyCode) return null;
    const amount = Number(total.units || 0) + Number(total.nanos || 0) / 1e9;
    return amount > 0 ? { amount: Math.round(amount * 100) / 100, currency: String(total.currencyCode).toUpperCase() } : null;
  } catch {
    return null;
  }
}

/// Acknowledged, then consumed: Google refunds what is not acknowledged
/// within three days, and an unconsumed spot cannot be bought again.
export async function googleSpotFinish(env, s, io) {
  const path = `purchases/products/${encodeURIComponent(s.productId)}/tokens/${encodeURIComponent(s.externalId)}`;
  if (!s.acknowledged) await googlePlay(env, "POST", `${path}:acknowledge`, io, {});
  if (!s.consumed) await googlePlay(env, "POST", `${path}:consume`, io, {});
}

// ------------------------------------------------------------
// The App Store: a consumable's signed transaction
// ------------------------------------------------------------

export async function appleSpotLookup(env, transactionId, io, verify = {}) {
  if (!/^\d{1,30}$/.test(String(transactionId || ""))) {
    throw new StoreError("Identifiant d'achat App Store invalide.", 400, "transaction");
  }
  const got = await appleGet(env, `/inApps/v1/transactions/${transactionId}`, io);
  const tx = await verifyAppleJws(got.body.signedTransactionInfo, verify);
  if (tx.bundleId !== appleBundle(env)) throw new StoreError("Cet achat n'est pas pour Marakaj.", 422, "bundle");
  if (!Object.hasOwn(APPLE_SPOT_PRODUCTS, tx.productId)) {
    throw new StoreError("Cet achat n'est pas une mise en avant.", 422, "product");
  }
  // Apple's price is in thousandths of the currency (since StoreKit 2).
  const price = tx.price != null && tx.currency ? Math.round(Number(tx.price) / 10) / 100 : null;
  return {
    platform: "apple",
    productId: tx.productId,
    kind: APPLE_SPOT_PRODUCTS[tx.productId],
    externalId: String(tx.transactionId || transactionId),
    state: tx.revocationDate ? "revoked" : "purchased",
    promotionId: uuidOr(tx.appAccountToken),
    orgId: null,
    environment: String(tx.environment || "").toLowerCase() === "sandbox" ? "sandbox" : "production",
    amount: price,
    currency: price != null ? String(tx.currency).toUpperCase() : null,
    raw: { transactionId: tx.transactionId, storefront: tx.storefront || null, type: tx.type || null,
      purchaseDate: tx.purchaseDate || null },
  };
}

// ------------------------------------------------------------
// The door
// ------------------------------------------------------------

function beginRefused(error) {
  if (error?.upstream === 401) return new StoreError("Votre session a expiré : reconnectez-vous.", 401, "session");
  if (error?.status === 400) {
    return new StoreError(error.message || "Seul un administrateur met l'entreprise en avant.", 403, "not_admin");
  }
  return error;
}

const SETTLE_REFUSED = {
  "another spot": ["Cet achat a déjà programmé une autre mise en avant.", 409, "replayed"],
  "no spot": ["Cette mise en avant n'existe plus.", 404, "no_spot"],
  product: ["Cet achat n'est pas cette mise en avant.", 422, "product"],
  sandbox: ["Achat de test refusé : un achat fait avec un compte de test ne programme une mise en avant que pour les comptes de test de Marakaj.", 403, "sandbox"],
  refunded: ["Cet achat a été remboursé : la mise en avant n'est pas programmée.", 409, "revoked"],
  refused: ["Cette mise en avant a été refusée par Marakaj : le paiement sera remboursé.", 409, "refused"],
  wrong_org: ["Cet achat a été fait pour une autre entreprise.", 409, "wrong_org"],
  vitrine: ["La vitrine est fermée : la mise en avant ne peut pas être programmée, le paiement sera remboursé.", 409, "ineligible"],
  feature: ["La mise en avant n'est pas disponible pour cette activité : le paiement sera remboursé.", 409, "ineligible"],
  article: ["Cet article n'est plus prêt pour la une (photo, prix, stock) : le paiement sera remboursé.", 409, "ineligible"],
};

/// The amount is the store's or Stripe's own; when the store says none
/// (Google without the order's financial data), spot_settle writes Mara's
/// zone price itself — the app's word is never sent.
async function settleSpot(env, io, s, promotionId, boughtBy, orgId = null) {
  const amount = s.amount ?? null;
  const currency = amount != null ? s.currency ?? null : null;
  const result = await io.rpcService(env, "spot_settle", {
    p_channel: s.platform,
    p_external_id: s.externalId,
    p_promotion_id: promotionId,
    p_product_id: s.productId,
    p_amount: amount,
    p_currency: currency,
    p_environment: s.environment,
    p_bought_by: boughtBy,
    p_raw: s.raw ?? null,
    p_amount_source: amount != null ? "store" : "mara",
    p_org_id: orgId,
  }, io.fetch);
  if (!result?.ok) {
    const [message, status, code] = SETTLE_REFUSED[result?.reason]
      || ["La mise en avant n'a pas pu être programmée.", 502, result?.reason || ""];
    const error = new StoreError(message, status, code);
    // Written by spot_settle (the money is to give back), and why.
    error.recorded = Boolean(result?.recorded);
    error.reason = result?.reason || "";
    throw error;
  }
  return result;
}

export async function spotVerify(body, userToken, env, io) {
  const platform = body?.platform;
  if (platform !== "apple" && platform !== "google") {
    throw new StoreError("Boutique inconnue.", 400, "platform");
  }
  const named = body?.promotion_id == null || body.promotion_id === "" ? null : uuidOr(body.promotion_id);
  if (body?.promotion_id && !named) throw new StoreError("Mise en avant inconnue.", 400, "spot");
  const begin = async (promotionId) => {
    try {
      return await io.rpcAs(env, userToken, "spot_verify_begin", { p_promotion_id: promotionId }, io.fetch);
    } catch (error) {
      throw beginRefused(error);
    }
  };
  // Postgres, as the caller, first when the spot is named.
  let begun = named ? await begin(named) : null;

  let s;
  if (platform === "apple") {
    if (!appleConfigured(env)) throw new StoreError("L'App Store n'est pas encore relié à Marakaj.", 503, "config");
    s = await appleSpotLookup(env, body?.transaction_id, io, io.verify);
    if (body?.product_id && body.product_id !== s.productId) {
      throw new StoreError("Cet achat n'est pas celui annoncé.", 422, "product");
    }
  } else {
    if (!googleConfigured(env)) throw new StoreError("Google Play n'est pas encore relié à Marakaj.", 503, "config");
    s = await googleSpotLookup(env, String(body?.product_id || ""), body?.token, io);
  }
  if (s.state === "pending") {
    throw new StoreError("Achat en attente de confirmation par la boutique.", 202, "pending");
  }
  if (s.state === "cancelled") throw new StoreError("Cet achat a été annulé.", 409, "cancelled");
  if (s.state === "revoked") throw new StoreError("Cet achat a été remboursé.", 409, "revoked");
  if (!s.promotionId) {
    throw new StoreError("Cet achat ne dit pas pour quelle mise en avant il a été fait.", 409, "no_spot");
  }
  if (named && s.promotionId !== named) {
    throw new StoreError("Cet achat a été fait pour une autre mise en avant.", 409, "wrong_spot");
  }
  if (!begun) begun = await begin(s.promotionId);
  // A spot gone (its business deleted): spot_settle records the payment
  // (« no spot ») for the platform to refund; nothing else is checked.
  if (!begun?.missing) {
    // Google also names the business: it must be the spot's.
    if (s.orgId && begun?.org_id && s.orgId !== String(begun.org_id).toLowerCase()) {
      throw new StoreError("Cet achat a été fait pour une autre entreprise.", 409, "wrong_org");
    }
    if (begun?.kind && begun.kind !== s.kind) {
      throw new StoreError("Cet achat n'est pas cette mise en avant.", 422, "product");
    }
  }

  if (s.amount == null && platform === "google") {
    const paid = await googleOrderTotal(env, s.orderId, io);
    if (paid) {
      s.amount = paid.amount;
      s.currency = paid.currency;
    }
  }
  const result = await settleSpot(env, io, s, s.promotionId, begun?.user_id || null, s.orgId || null);
  if (platform === "google") await googleSpotFinish(env, s, io);
  return {
    ok: true,
    promotion_id: result.promotion_id,
    org_id: result.org_id,
    granted: Boolean(result.granted),
    starts_at: result.starts_at || null,
    ends_at: result.ends_at || null,
  };
}

// ------------------------------------------------------------
// Stripe: one payment by card on the website
// ------------------------------------------------------------

export async function stripeSpotCheckout(body, userToken, env, io) {
  const begun = await io.rpcAs(env, userToken, "spot_stripe_begin", {
    p_promotion_id: body?.promotion_id,
  }, io.fetch);
  const origin = (env.APP_ORIGIN || "").replace(/\/$/, "");
  const back = `${origin}/o/${begun.org_id}/administration/parametres?partie=vitrine`;
  const what = begun.kind === "shop" ? "La vitrine à la une" : "Un article à la une";
  const session = await createPaymentCheckout(env, {
    reference: begun.promotion_id,
    name: ["Marakaj", `${what}, ${begun.days || 7} jours`, begun.label || null,
      priceLabel(begun.price, begun.price_currency), begun.org_name].filter(Boolean).join(" · "),
    amount: begun.amount,
    currency: begun.currency,
    email: begun.email || null,
    metadata: {
      kind: "spot",
      promotion_id: begun.promotion_id,
      org_id: begun.org_id,
      spot_kind: begun.kind,
    },
    successUrl: `${back}&spot=ok`,
    cancelUrl: `${back}&spot=annule`,
  }, io.fetch);
  return { url: session.url, id: session.id };
}

/// Whether a Stripe event is a spot's one-time payment.
export function isSpotEvent(event) {
  const obj = event?.data?.object || {};
  return (event?.type === "checkout.session.completed"
          || event?.type === "checkout.session.async_payment_succeeded")
    && obj.mode === "payment" && obj.metadata?.kind === "spot";
}

/// A spot's Checkout Session, read again from Stripe and programmed once.
export async function onStripeSpotEvent(event, env, io) {
  const id = event?.data?.object?.id;
  if (!id) return { ignored: "no session" };
  const session = await getCheckoutSession(env, id, io.fetch);
  if (session?.mode !== "payment" || session?.metadata?.kind !== "spot") return { ignored: "not a spot" };
  if (session.payment_status !== "paid") return { ignored: `payment ${session.payment_status || "unknown"}` };
  const promotionId = uuidOr(session.metadata?.promotion_id) || uuidOr(session.client_reference_id);
  if (!promotionId) return { ignored: "no spot on the session" };
  const currency = String(session.currency || "").toUpperCase();
  const minor = Number(session.amount_total ?? 0);
  const amount = currency === "XOF" || currency === "XAF" ? minor : Math.round(minor) / 100;
  const kind = session.metadata?.spot_kind === "shop" ? "shop" : "article";
  const pi = (typeof session.payment_intent === "string" ? session.payment_intent : session.payment_intent?.id) || null;
  // Refunded or disputed before it was settled (the events out of order):
  // its mark, and never a spot.
  if (pi) {
    const intent = await getPaymentIntent(env, pi, io.fetch);
    const charge = typeof intent?.latest_charge === "object" ? intent.latest_charge : null;
    if (charge?.refunded || charge?.disputed || Number(charge?.amount_refunded || 0) > 0) {
      await spotRefund(env, io, "stripe", pi, charge?.disputed ? "stripe disputed before settle" : "stripe refunded before settle");
      return { ignored: "refunded" };
    }
  }
  try {
    const result = await settleSpot(env, io, {
      platform: "stripe",
      productId: `stripe:${kind}`,
      externalId: session.id,
      environment: session.livemode === false ? "sandbox" : "production",
      amount,
      currency,
      raw: { payment_intent: pi },
    }, promotionId, null);
    return { settled: true, granted: Boolean(result.granted), promotion_id: result.promotion_id };
  } catch (error) {
    // Refused for good and written (the spot gone, refused, no longer
    // eligible, a test payment, the wrong product): the card is refunded
    // at once, and the refund written on the payment. A failure of the
    // refund is Stripe's retry: the settle answers the same refusal.
    if (error instanceof StoreError && error.recorded && pi) {
      await refundPaymentIntent(env, pi, error.reason, io.fetch);
      await spotRefund(env, io, "stripe", session.id, `stripe auto-refund (${error.reason})`);
      console.warn(`stripe spot: refused (${error.reason}), refunded`);
      return { ignored: error.code || String(error.status), refunded: true };
    }
    // What no retry will change is answered 200 (Stripe retries the rest
    // for three days), and logged.
    if (error instanceof StoreError && error.status < 500) {
      console.warn(`stripe spot: ignored (${error.code || error.status})`);
      return { ignored: error.code || String(error.status) };
    }
    throw error;
  }
}

/// Google's word that a one-time spot was bought (RTDN PURCHASED) — a
/// pending purchase completed while the app was closed: read from Google
/// as /store/spot-verify does, programmed for the spot and the business
/// the purchase itself names (spot_settle checks they are one), then
/// acknowledged and consumed. Refused for good: left unacknowledged, so
/// Google refunds it.
export async function googleSpotPurchased(env, note, io) {
  if (!Object.hasOwn(GOOGLE_SPOT_PRODUCTS, note.sku)) return { ignored: "not a spot" };
  const s = await googleSpotLookup(env, note.sku, note.token, io);
  if (s.state !== "purchased") return { ignored: s.state };
  if (s.consumed) return { ignored: "consumed" };
  if (!s.promotionId || !s.orgId) return { ignored: "no spot" };
  if (s.amount == null) {
    const paid = await googleOrderTotal(env, s.orderId, io);
    if (paid) {
      s.amount = paid.amount;
      s.currency = paid.currency;
    }
  }
  try {
    const result = await settleSpot(env, io, s, s.promotionId, null, s.orgId);
    await googleSpotFinish(env, s, io);
    return { settled: true, granted: Boolean(result.granted), promotion_id: result.promotion_id };
  } catch (error) {
    if (error instanceof StoreError && error.status < 500) {
      console.warn(`google spot-notify: refused (${error.code || error.status})`);
      return { ignored: error.code || String(error.status) };
    }
    throw error;
  }
}


// ------------------------------------------------------------
// A payment taken back: the store or Stripe refunded it
// ------------------------------------------------------------

/// Written once on the spot's payment, and the spot ends (spot_refund):
/// a running one now, one still waiting its turn cancelled. A payment
/// that is not a spot's (Mara Pro's, unknown) changes nothing.
export async function spotRefund(env, io, channel, externalId, reason) {
  const result = await io.rpcService(env, "spot_refund", {
    p_channel: channel,
    p_external_id: externalId,
    p_reason: reason,
  }, io.fetch);
  if (!result?.ok) return { ignored: result?.reason || "unknown" };
  return { refunded: true, already: Boolean(result.already), promotion_id: result.promotion_id || null,
    spot: result.spot || null };
}

/// Whether a Stripe event may be a spot's payment taken back.
export function isSpotRefundEvent(event) {
  return event?.type === "charge.refunded" || event?.type === "charge.dispute.created";
}

/// A refund or a dispute: its PaymentIntent read again from Stripe — a
/// spot's (metadata kind = spot), fully refunded or disputed — then the
/// spot ends. A partial refund is logged and changes nothing.
export async function onStripeSpotRefund(event, env, io) {
  const obj = event?.data?.object || {};
  const pi = typeof obj.payment_intent === "string" ? obj.payment_intent : obj.payment_intent?.id;
  if (!pi) return { ignored: "no payment" };
  const intent = await getPaymentIntent(env, pi, io.fetch);
  if (intent?.metadata?.kind !== "spot") return { ignored: "not a spot" };
  const charge = typeof intent.latest_charge === "object" ? intent.latest_charge : null;
  const dispute = event.type === "charge.dispute.created";
  if (dispute ? !charge?.disputed : !charge?.refunded) {
    console.warn(`stripe spot: ${dispute ? "dispute" : "refund"} not confirmed by Stripe (partial or none)`);
    return { ignored: dispute ? "not disputed" : "partial refund" };
  }
  return spotRefund(env, io, "stripe", pi, dispute ? "stripe charge.dispute.created" : "stripe charge.refunded");
}
