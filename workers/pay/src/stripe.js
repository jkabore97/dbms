// Stripe's side of kaj-pay: Kaj Pro by card, as a subscription (082).
//
// Stripe is for the subscription only — an order is paid by Wave. The
// price is the platform's (pro_price_month / pro_price_year, set from the
// console), sent to Stripe as the line's own price on each new checkout, so
// there is no product to keep in step on Stripe's dashboard. XOF is one of
// Stripe's zero-decimal currencies: 3000 F is unit_amount 3000.

import { constantTimeEqual, hmacHex } from "./wave.js";

const STRIPE = "https://api.stripe.com";

/// A Checkout Session in subscription mode. Returns { id, url, ... }.
export async function createCheckout(env, args, fetchImpl = fetch) {
  const label = args.period === "year" ? "annuel" : "mensuel";
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
    "line_items[0][price_data][product_data][name]": `Mara Pro · ${label} · ${args.orgName || ""}`.trim(),
    "metadata[org_id]": args.orgId,
    "metadata[period]": args.period,
    "subscription_data[metadata][org_id]": args.orgId,
    "subscription_data[metadata][period]": args.period,
  };
  if (args.customerId) params.customer = args.customerId;
  else if (args.email) params.customer_email = args.email;
  return stripeCall(env, "POST", "/v1/checkout/sessions", params, fetchImpl);
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

async function stripeCall(env, method, path, params, fetchImpl) {
  const init = {
    method,
    headers: { Authorization: `Bearer ${env.STRIPE_SECRET_KEY}` },
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
