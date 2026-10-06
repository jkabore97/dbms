// Plays Stripe and the database against workers/pay's card subscription.
//
//   node --test workers/pay/test
//
// Stripe: the signature on its webhook ("<t>.<body>"), a Checkout Session
// it creates (form-encoded), a subscription it answers with, old shape or
// new. The database: stripe_begin / stripe_customer_of / stripe_settle.

import assert from "node:assert/strict";
import { test } from "node:test";

import worker, { onStripeEvent, stripeCheckout, stripePortal } from "../src/index.js";
import { hmacHex } from "../src/wave.js";
import { readSubscription, subscriptionOf, verifyStripeSignature } from "../src/stripe.js";

const env = {
  SUPABASE_URL: "https://db.example",
  SUPABASE_PUBLISHABLE_KEY: "pub",
  SUPABASE_SERVICE_ROLE_KEY: "service",
  STRIPE_SECRET_KEY: "sk_test_kaj",
  STRIPE_WEBHOOK_SECRET: "whsec_kaj",
  APP_ORIGIN: "https://kaj.example/",
};

const ORG = "52000000-0000-0000-0000-000000000001";

/// A fake fetch: records every call (form bodies decoded), answers by URL.
function fakeFetch(answers) {
  const calls = [];
  const fetchImpl = async (url, init) => {
    let body = null;
    if (init?.body) {
      body = init.headers?.["Content-Type"] === "application/x-www-form-urlencoded"
        ? Object.fromEntries(new URLSearchParams(init.body))
        : JSON.parse(init.body);
    }
    calls.push({ url, method: init?.method, headers: init?.headers, body });
    for (const [match, answer] of answers) {
      if (url.endsWith(match)) {
        const value = typeof answer === "function" ? answer(body) : answer;
        const status = value?.__status || 200;
        return new Response(JSON.stringify(value?.__body ?? value), { status });
      }
    }
    return new Response("null", { status: 200 });
  };
  return { fetchImpl, calls };
}

const subscription = (over = {}) => ({
  id: "sub_1",
  customer: "cus_1",
  status: "active",
  cancel_at_period_end: false,
  metadata: { org_id: ORG, period: "month" },
  items: { data: [{ current_period_end: 1_900_000_000, price: { recurring: { interval: "month" } } }] },
  ...over,
});

test("Stripe's signature is over '<t>.<body>', and goes stale", async () => {
  const body = '{"type":"invoice.paid"}';
  const t = 1_800_000_000;
  const sig = await hmacHex("whsec_kaj", `${t}.${body}`);
  assert.equal(await verifyStripeSignature(`t=${t},v1=${sig}`, body, "whsec_kaj", t + 10), true);
  assert.equal(await verifyStripeSignature(`t=${t},v1=bad,v1=${sig}`, body, "whsec_kaj", t), true,
    "any v1 may match (a secret being rolled)");
  assert.equal(await verifyStripeSignature(`t=${t},v1=${sig}`, body + " ", "whsec_kaj", t), false);
  assert.equal(await verifyStripeSignature(`t=${t},v1=${await hmacHex("whsec_kaj", `${t}${body}`)}`,
    body, "whsec_kaj", t), false, "Wave's form (no dot) is not Stripe's");
  assert.equal(await verifyStripeSignature(`t=${t},v1=${sig}`, body, "whsec_kaj", t + 301), false);
  assert.equal(await verifyStripeSignature(null, body, "whsec_kaj", t), false);
});

test("the checkout is the database's price, as a monthly or yearly subscription", async () => {
  const { fetchImpl, calls } = fakeFetch([
    ["/rpc/stripe_begin", { org_id: ORG, org_name: "Boutique Carte", period: "year",
      amount: 30000, currency: "xof", customer_id: null, email: "awa@example.com" }],
    ["/v1/checkout/sessions", { id: "cs_1", url: "https://checkout.stripe.com/c/cs_1" }],
  ]);
  const out = await stripeCheckout({ org_id: ORG, period: "year", amount: 1 }, "user.jwt", env,
    { fetch: fetchImpl });
  assert.deepEqual(out, { url: "https://checkout.stripe.com/c/cs_1", id: "cs_1" });

  const [begin, session] = calls;
  assert.equal(begin.headers.apikey, "pub", "stripe_begin runs as the owner, not the service");
  assert.equal(begin.headers.Authorization, "Bearer user.jwt");
  assert.deepEqual(begin.body, { p_org_id: ORG, p_period: "year" }, "the app's amount is not sent");

  assert.equal(session.headers.Authorization, "Bearer sk_test_kaj");
  const p = session.body;
  assert.equal(p.mode, "subscription");
  assert.equal(p["line_items[0][price_data][unit_amount]"], "30000", "XOF is zero-decimal");
  assert.equal(p["line_items[0][price_data][currency]"], "xof");
  assert.equal(p["line_items[0][price_data][recurring][interval]"], "year");
  assert.equal(p["subscription_data[metadata][org_id]"], ORG);
  assert.equal(p.client_reference_id, ORG);
  assert.equal(p.customer_email, "awa@example.com");
  assert.equal(p.customer, undefined);
  assert.equal(p.success_url, `https://kaj.example/o/${ORG}/kaj-pro?stripe=ok`);
  assert.equal(p.cancel_url, `https://kaj.example/o/${ORG}/kaj-pro?stripe=annule`);
});

test("a returning business keeps its Stripe customer", async () => {
  const { fetchImpl, calls } = fakeFetch([
    ["/rpc/stripe_begin", { org_id: ORG, org_name: "B", period: "month", amount: 3000,
      currency: "xof", customer_id: "cus_1", email: "awa@example.com" }],
    ["/v1/checkout/sessions", { id: "cs_2", url: "https://checkout.stripe.com/c/cs_2" }],
  ]);
  await stripeCheckout({ org_id: ORG, period: "month" }, "t", env, { fetch: fetchImpl });
  assert.equal(calls[1].body.customer, "cus_1");
  assert.equal(calls[1].body.customer_email, undefined);
  assert.equal(calls[1].body["line_items[0][price_data][recurring][interval]"], "month");
});

test("the database's refusal reaches the owner, and nothing is created at Stripe", async () => {
  const { fetchImpl, calls } = fakeFetch([
    ["/rpc/stripe_begin", { __status: 400,
      __body: { message: "Seul un administrateur abonne l'entreprise à Kaj Pro" } }],
  ]);
  await assert.rejects(stripeCheckout({ org_id: ORG }, "t", env, { fetch: fetchImpl }),
    (e) => e.status === 400 && /Seul un administrateur/.test(e.message));
  assert.equal(calls.length, 1);
});

test("the portal opens only for a business with a Stripe customer", async () => {
  const yes = fakeFetch([
    ["/rpc/stripe_customer_of", "cus_1"],
    ["/v1/billing_portal/sessions", { url: "https://billing.stripe.com/p/1" }],
  ]);
  assert.deepEqual(await stripePortal({ org_id: ORG }, "t", env, { fetch: yes.fetchImpl }),
    { url: "https://billing.stripe.com/p/1" });
  assert.equal(yes.calls[1].body.customer, "cus_1");
  assert.equal(yes.calls[1].body.return_url, `https://kaj.example/o/${ORG}/kaj-pro`);

  const no = fakeFetch([["/rpc/stripe_customer_of", null]]);
  await assert.rejects(stripePortal({ org_id: ORG }, "t", env, { fetch: no.fetchImpl }),
    (e) => e.status === 404);
  assert.equal(no.calls.length, 1);
});

test("a subscription reads the same in the old shape and the new", () => {
  const fresh = readSubscription(subscription());
  assert.deepEqual(fresh, {
    orgId: ORG, subscriptionId: "sub_1", customerId: "cus_1", status: "active",
    period: "month", periodEnd: new Date(1_900_000_000 * 1000).toISOString(), cancelAtEnd: false,
  });
  const old = readSubscription(subscription({
    current_period_end: 1_900_000_000,
    items: { data: [{ plan: { interval: "month" } }] },
  }));
  assert.equal(old.periodEnd, fresh.periodEnd);
  assert.equal(old.period, "month");
});

test("each event names its subscription", () => {
  assert.deepEqual(subscriptionOf({ type: "checkout.session.completed",
    data: { object: { subscription: "sub_1", client_reference_id: ORG } } }), { id: "sub_1", orgId: ORG });
  assert.equal(subscriptionOf({ type: "invoice.paid",
    data: { object: { parent: { subscription_details: { subscription: "sub_1" } } } } }).id, "sub_1");
  assert.equal(subscriptionOf({ type: "invoice.paid", data: { object: { subscription: "sub_1" } } }).id,
    "sub_1");
  assert.equal(subscriptionOf({ type: "customer.subscription.deleted",
    data: { object: { id: "sub_1" } } }).id, "sub_1");
  assert.equal(subscriptionOf({ type: "charge.refunded", data: { object: {} } }), null);
});

test("an event is settled from Stripe's own fresh copy, by the service role", async () => {
  const { fetchImpl, calls } = fakeFetch([
    ["/v1/subscriptions/sub_1", subscription({ status: "canceled", cancel_at_period_end: true })],
    ["/rpc/stripe_settle", { ok: true, active: false }],
  ]);
  // The event's copy says active; Stripe's latest says cancelled.
  const out = await onStripeEvent({ type: "customer.subscription.updated",
    data: { object: subscription() } }, env, { fetch: fetchImpl });
  assert.deepEqual(out, { settled: true, active: false });
  assert.equal(calls[0].method, "GET");
  const settle = calls[1];
  assert.equal(settle.headers.apikey, "service");
  assert.deepEqual(settle.body, {
    p_org_id: ORG, p_subscription_id: "sub_1", p_customer_id: "cus_1", p_status: "canceled",
    p_period: "month", p_period_end: new Date(1_900_000_000 * 1000).toISOString(),
    p_cancel_at_end: true,
  });
});

test("an event with no subscription, or no business, settles nothing", async () => {
  const { fetchImpl, calls } = fakeFetch([
    ["/v1/subscriptions/sub_9", subscription({ id: "sub_9", metadata: {} })],
  ]);
  assert.deepEqual(await onStripeEvent({ type: "payment_intent.created", data: { object: {} } },
    env, { fetch: fetchImpl }), { ignored: "payment_intent.created" });
  assert.deepEqual(await onStripeEvent({ type: "invoice.paid",
    data: { object: { subscription: "sub_9" } } }, env, { fetch: fetchImpl }),
    { ignored: "no business on the subscription" });
  assert.equal(calls.filter((c) => c.url.includes("/rpc/")).length, 0);
});

test("the webhook door refuses a bad signature and asks Stripe to retry a failure", async () => {
  const body = JSON.stringify({ type: "invoice.paid", data: { object: { subscription: "sub_1" } } });
  const bad = await worker.fetch(new Request("https://pay.example/v1/stripe", {
    method: "POST", body, headers: { "Stripe-Signature": "t=1,v1=00" } }), env);
  assert.equal(bad.status, 401);

  const t = Math.floor(Date.now() / 1000);
  const sig = await hmacHex(env.STRIPE_WEBHOOK_SECRET, `${t}.${body}`);
  const real = globalThis.fetch;
  globalThis.fetch = async () => new Response('{"error":{"message":"down"}}', { status: 500 });
  try {
    const down = await worker.fetch(new Request("https://pay.example/v1/stripe", {
      method: "POST", body, headers: { "Stripe-Signature": `t=${t},v1=${sig}` } }), env);
    assert.equal(down.status, 500, "a failure is retried by Stripe");
  } finally {
    globalThis.fetch = real;
  }
});

test("without the Stripe key the card doors say so", async () => {
  const res = await worker.fetch(new Request("https://pay.example/v1/stripe/checkout", {
    method: "POST", body: "{}", headers: { Authorization: "Bearer t" } }),
    { ...env, STRIPE_SECRET_KEY: "" });
  assert.equal(res.status, 503);
  const health = await (await worker.fetch(new Request("https://pay.example/v1/health"), env)).json();
  assert.equal(health.stripe, true);
});
