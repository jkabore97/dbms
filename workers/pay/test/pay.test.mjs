// Plays Wave and the database against workers/pay.
//
//   node --test workers/pay/test
//
// Wave: the signature it puts on a webhook (checked here the way it is
// computed there), a session it creates, a payout it sends or fails. The
// database: wave_begin / wave_attach / wave_settle / wave_payout_done /
// wave_payout_queue, answered from a little table so each step is visible.

import assert from "node:assert/strict";
import { test } from "node:test";

import { checkout, onWebhook, retryPayouts } from "../src/index.js";
import { hmacHex, verifySignature, wholeFrancs } from "../src/wave.js";

const env = {
  SUPABASE_URL: "https://db.example",
  SUPABASE_PUBLISHABLE_KEY: "pub",
  SUPABASE_SERVICE_ROLE_KEY: "service",
  WAVE_API_KEY: "wave_bf_key",
  WAVE_WEBHOOK_SECRET: "whsec",
  APP_ORIGIN: "https://kaj.example/",
};

/// A fake fetch: records every call, answers by URL.
function fakeFetch(answers) {
  const calls = [];
  const fetchImpl = async (url, init) => {
    const body = init?.body ? JSON.parse(init.body) : null;
    calls.push({ url, headers: init.headers, body });
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

test("francs are whole, as Wave wants them", () => {
  assert.equal(wholeFrancs("5000.00"), "5000");
  assert.equal(wholeFrancs(4500), "4500");
});

test("a signature is checked over the timestamp and the raw body, and goes stale", async () => {
  const body = '{"type":"checkout.session.completed"}';
  const t = 1_800_000_000;
  const sig = await hmacHex("whsec", `${t}${body}`);
  assert.equal(await verifySignature(`t=${t},v1=${sig}`, body, "whsec", t + 10), true);
  assert.equal(await verifySignature(`t=${t},v1=${sig}`, body + " ", "whsec", t + 10), false,
    "a changed body fails");
  assert.equal(await verifySignature(`t=${t},v1=${sig}`, body, "other", t + 10), false,
    "another secret fails");
  assert.equal(await verifySignature(`t=${t},v1=${sig}`, body, "whsec", t + 301), false,
    "older than five minutes fails");
  assert.equal(await verifySignature(null, body, "whsec", t), false);
});

test("checkout: the person's token begins it, Wave's session is attached", async () => {
  const { fetchImpl, calls } = fakeFetch([
    ["/rpc/wave_begin", { payment_id: "pay-1", client_reference: "pay-1", amount: 5000,
                          currency: "XOF", aggregated_merchant_id: "am-47" }],
    ["/v1/checkout/sessions", { id: "cos-1", wave_launch_url: "https://pay.wave.com/c/cos-1" }],
    ["/rpc/wave_attach", null],
  ]);
  const out = await checkout({ kind: "order", ref: "o1", method: "card" }, "user-jwt", env, { fetch: fetchImpl });
  assert.deepEqual(out, { url: "https://pay.wave.com/c/cos-1", payment_id: "pay-1", method: "card" });

  const begin = calls[0];
  assert.equal(begin.headers.Authorization, "Bearer user-jwt", "begun as the person, not the service");
  assert.equal(begin.headers.apikey, "pub");
  assert.equal(begin.body.p_method, "card");

  const session = calls[1];
  assert.equal(session.headers.Authorization, "Bearer wave_bf_key");
  assert.equal(session.body.amount, "5000");
  assert.equal(session.body.aggregated_merchant_id, "am-47");
  assert.equal(session.body.success_url, "https://kaj.example/paiement/pay-1?issue=ok");

  const attach = calls[2];
  assert.equal(attach.headers.Authorization, "Bearer service");
  assert.equal(attach.body.p_session_id, "cos-1");
});

test("checkout: the database's refusal reaches the person in its own words", async () => {
  const { fetchImpl } = fakeFetch([
    ["/rpc/wave_begin", { __status: 400, __body: { message: "Cette commande est déjà payée" } }],
  ]);
  await assert.rejects(
    checkout({ kind: "order", ref: "o1" }, "user-jwt", env, { fetch: fetchImpl }),
    (e) => e.message === "Cette commande est déjà payée" && e.status === 400);
});

test("webhook: paid → settled → the shop paid, with the payment id as idempotency key", async () => {
  const { fetchImpl, calls } = fakeFetch([
    ["/rpc/wave_settle", { payment_id: "pay-1", amount: 4500, currency: "XOF",
                           mobile: "+22670470001", name: "Boutique Wave" }],
    ["/v1/payout", { id: "pt-1", status: "succeeded" }],
    ["/rpc/wave_payout_done", null],
  ]);
  const { sendPayout } = await import("../src/wave.js");
  const out = await onWebhook({
    type: "checkout.session.completed",
    data: { id: "cos-1", client_reference: "pay-1", payment_status: "succeeded", transaction_id: "T1" },
  }, env, { fetch: fetchImpl, sendPayout });
  assert.deepEqual(out, { settled: true, payout: true });
  const payout = calls.find((c) => c.url.endsWith("/v1/payout"));
  assert.equal(payout.headers["idempotency-key"], "pay-1");
  assert.equal(payout.body.receive_amount, "4500");
  assert.equal(payout.body.mobile, "+22670470001");
  const done = calls.find((c) => c.url.endsWith("/rpc/wave_payout_done"));
  assert.equal(done.body.p_ok, true);
  assert.equal(done.body.p_payout_id, "pt-1");
});

test("webhook: a failed payment settles as failed and pays nobody", async () => {
  const { fetchImpl, calls } = fakeFetch([["/rpc/wave_settle", null]]);
  const out = await onWebhook({
    type: "checkout.session.payment_failed",
    data: { id: "cos-2", client_reference: "pay-2" },
  }, env, { fetch: fetchImpl, sendPayout: async () => assert.fail("no payout") });
  assert.deepEqual(out, { settled: false });
  assert.equal(calls[0].body.p_succeeded, false);
});

test("a payout that throws is recorded as failed, and the cron tries it again", async () => {
  const { fetchImpl, calls } = fakeFetch([
    ["/rpc/wave_payout_queue", [{ payment_id: "pay-3", amount: 1000, currency: "XOF",
                                  mobile: "+22670000003", name: "B" }]],
    ["/rpc/wave_payout_done", null],
  ]);
  let tries = 0;
  const flaky = async () => {
    tries++;
    if (tries === 1) throw new Error("timeout");
    return { id: "pt-3", status: "succeeded" };
  };
  assert.equal(await retryPayouts(env, { fetch: fetchImpl, sendPayout: flaky }), 0);
  const failed = calls.filter((c) => c.url.endsWith("/rpc/wave_payout_done")).pop();
  assert.equal(failed.body.p_ok, false);
  assert.equal(failed.body.p_error, "timeout");
  assert.equal(await retryPayouts(env, { fetch: fetchImpl, sendPayout: flaky }), 1);
});
