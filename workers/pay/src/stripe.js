// Stripe's side of kaj-pay: Kaj Pro by card, as a subscription (082), and
// since 139 a spot (« Mettre en avant ») by card, as one payment.
//
// An order is paid by Wave. The price is the platform's, read by the
// database and sent to Stripe as the line's own price on each new
// checkout, so there is no product to keep in step on Stripe's dashboard.
// 121 charged dollars converted from the FCFA price at stripe_xof_per_usd;
// since 139 stripe_begin() and spot_stripe_begin() answer the business's
// zone price in the zone's own currency — FCFA (XOF, or XAF at the same
// number: zero-decimal at Stripe, 2 900 F is 2900), euros or dollars (in
// cents) — and the Worker sends the amount and currency as they are and
// never converts. The line's name says the price as the app shows it
// (« Mara Pro · Mensuel · 2 900 FCFA · <business> »).

import { constantTimeEqual, hmacHex } from "./wave.js";

const STRIPE = "https://api.stripe.com";

/// A Checkout Session in subscription mode. Returns { id, url, ... }.
export async function createCheckout(env, args, fetchImpl = fetch) {
  const label = args.period === "year" ? "Annuel" : "Mensuel";
  const price = priceLabel(args.price, args.priceCurrency);
  const params = {
    mode: "subscription",
    locale: "fr",
    client_reference_id: args.orgId,
    success_url: args.successUrl,
    cancel_url: args.cancelUrl,
    "line_items[0][quantity]": "1",
    "line_items[0][price_data][currency]": String(args.currency || "xof").toLowerCase(),
    "line_items[0][price_data][unit_amount]": String(Math.round(Number(args.amount))),
    "line_items[0][price_data][recurring][interval]": args.period === "year" ? "year" : "month",
    "line_items[0][price_data][product_data][name]":
      ["Marakaj Pro", label, price, args.orgName].filter(Boolean).join(" · "),
    "metadata[org_id]": args.orgId,
    "metadata[period]": args.period,
    "subscription_data[metadata][org_id]": args.orgId,
    "subscription_data[metadata][period]": args.period,
  };
  if (args.customerId) params.customer = args.customerId;
  else if (args.email) params.customer_email = args.email;
  return stripeCall(env, "POST", "/v1/checkout/sessions", params, fetchImpl);
}

/// The price as the app shows it: « 15 000 FCFA », « 4,99 EUR ». Nothing
/// without one (a database before 121 sends none).
export function priceLabel(amount, currency) {
  const n = Number(amount);
  if (!Number.isFinite(n) || n <= 0) return "";
  const code = String(currency || "").toUpperCase();
  const cfa = code === "XOF" || code === "XAF";
  const unit = cfa ? "FCFA" : code;
  const whole = cfa ? Math.round(n) : Math.trunc(n);
  const digits = String(whole).replace(/\B(?=(\d{3})+(?!\d))/g, " ");
  const cents = cfa ? 0 : Math.round((n - whole) * 100);
  return `${digits}${cents ? `,${String(cents).padStart(2, "0")}` : ""} ${unit}`.trim();
}

/// A Checkout Session for one payment (139: a spot). Returns { id, url }.
/// [amount] is in Stripe's minor units, as the database answered it.
export async function createPaymentCheckout(env, args, fetchImpl = fetch) {
  const params = {
    mode: "payment",
    locale: "fr",
    client_reference_id: args.reference,
    success_url: args.successUrl,
    cancel_url: args.cancelUrl,
    "line_items[0][quantity]": "1",
    "line_items[0][price_data][currency]": String(args.currency || "xof").toLowerCase(),
    "line_items[0][price_data][unit_amount]": String(Math.round(Number(args.amount))),
    "line_items[0][price_data][product_data][name]": args.name,
    "payment_method_types[0]": "card",
  };
  for (const [k, v] of Object.entries(args.metadata || {})) {
    params[`metadata[${k}]`] = v;
    params[`payment_intent_data[metadata][${k}]`] = v;
  }
  if (args.email) params.customer_email = args.email;
  return stripeCall(env, "POST", "/v1/checkout/sessions", params, fetchImpl);
}

/// A Checkout Session as Stripe holds it now.
export async function getCheckoutSession(env, id, fetchImpl = fetch) {
  return stripeCall(env, "GET", `/v1/checkout/sessions/${encodeURIComponent(id)}`, null, fetchImpl);
}

/// A PaymentIntent as Stripe holds it now, with its latest charge (139: a
/// spot's refund or dispute is read here, never from the event).
export async function getPaymentIntent(env, id, fetchImpl = fetch) {
  return stripeCall(env, "GET",
    `/v1/payment_intents/${encodeURIComponent(id)}?expand%5B%5D=latest_charge`, null, fetchImpl);
}

/// Stripe's own page where the owner changes the card or cancels.
export async function createPortal(env, args, fetchImpl = fetch) {
  return stripeCall(env, "POST", "/v1/billing_portal/sessions", {
    customer: args.customerId,
    return_url: args.returnUrl,
  }, fetchImpl);
}

export async function getSubscription(env, id, fetchImpl = fetch) {
  return stripeCall(env, "GET", `/v1/subscriptions/${encodeURIComponent(id)}`, null, fetchImpl);
}

/// What the database needs from a subscription object, whichever API
/// version wrote it: the paid period's end moved from the subscription to
/// its items in 2025.
export function readSubscription(sub) {
  const item = sub?.items?.data?.[0] || {};
  const end = sub?.current_period_end ?? item.current_period_end ?? null;
  const interval = item.price?.recurring?.interval || item.plan?.interval || sub?.metadata?.period || null;
  return {
    orgId: sub?.metadata?.org_id || null,
    subscriptionId: sub?.id || null,
    customerId: typeof sub?.customer === "string" ? sub.customer : sub?.customer?.id || null,
    status: sub?.status || null,
    period: interval === "year" || interval === "month" ? interval : null,
    periodEnd: end ? new Date(end * 1000).toISOString() : null,
    cancelAtEnd: Boolean(sub?.cancel_at_period_end),
  };
}

/// The subscription an event is about, and the business if the event says.
export function subscriptionOf(event) {
  const obj = event?.data?.object || {};
  switch (event?.type) {
    case "checkout.session.completed":
      return { id: obj.subscription || null, orgId: obj.client_reference_id || obj.metadata?.org_id || null };
    case "customer.subscription.created":
    case "customer.subscription.updated":
    case "customer.subscription.deleted":
      return { id: obj.id || null, orgId: obj.metadata?.org_id || null, object: obj };
    case "invoice.paid":
    case "invoice.payment_failed":
      return {
        id: obj.subscription
          || obj.parent?.subscription_details?.subscription
          || obj.lines?.data?.[0]?.subscription
          || null,
        orgId: obj.parent?.subscription_details?.metadata?.org_id
          || obj.subscription_details?.metadata?.org_id
          || null,
      };
    default:
      return null;
  }
}

/// Stripe-Signature: t=<seconds>,v1=<hex>[,v1=…]; HMAC-SHA256 of
/// "<t>.<raw body>" with the endpoint's secret; five minutes' tolerance.
export async function verifyStripeSignature(header, rawBody, secret,
  nowSeconds = Math.floor(Date.now() / 1000)) {
  if (!header || !secret) return false;
  let timestamp = null;
  const signatures = [];
  for (const part of header.split(",")) {
    const [key, value] = part.trim().split("=", 2);
    if (key === "t") timestamp = value;
    else if (key === "v1" && value) signatures.push(value.toLowerCase());
  }
  if (!timestamp || signatures.length === 0) return false;
  const t = Number(timestamp);
  if (!Number.isFinite(t) || Math.abs(nowSeconds - t) > 300) return false;
  const expected = await hmacHex(secret, `${timestamp}.${rawBody}`);
  return signatures.some((s) => constantTimeEqual(s, expected));
}

/// A spot's payment refunded at once (139): the spot it was for is gone,
/// refused or no longer eligible. One refund per PaymentIntent, whatever
/// the retries (Stripe's idempotency key); one already refunded is done.
export async function refundPaymentIntent(env, paymentIntent, reason, fetchImpl = fetch) {
  try {
    return await stripeCall(env, "POST", "/v1/refunds", {
      payment_intent: paymentIntent,
      "metadata[kind]": "spot",
      "metadata[why]": reason || "",
    }, fetchImpl, { "Idempotency-Key": `mara-spot-refund-${paymentIntent}` });
  } catch (error) {
    if (/already been refunded|already refunded/i.test(error.message || "")) return { already: true };
    throw error;
  }
}

async function stripeCall(env, method, path, params, fetchImpl, headers = {}) {
  const init = {
    method,
    headers: { Authorization: `Bearer ${env.STRIPE_SECRET_KEY}`, ...headers },
  };
  if (params) {
    init.headers["Content-Type"] = "application/x-www-form-urlencoded";
    init.body = new URLSearchParams(
      Object.entries(params).filter(([, v]) => v !== undefined && v !== null && v !== "")).toString();
  }
  const response = await fetchImpl(`${STRIPE}${path}`, init);
  const text = await response.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch { data = { raw: text }; }
  if (!response.ok) {
    const error = new Error(data?.error?.message || `Stripe answered ${response.status}`);
    error.status = response.status >= 500 ? 502 : 400;
    throw error;
  }
  return data;
}
