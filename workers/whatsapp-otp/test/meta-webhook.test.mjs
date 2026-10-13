// Meta's webhook (batch 136): the subscription check and signed events.
//
//   node --test workers/whatsapp-otp/test

import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import { test } from "node:test";

import { metaSummary, route } from "../src/index.js";

const env = { META_VERIFY_TOKEN: "verify-me-0123456789", META_APP_SECRET: "app-secret-for-tests" };
const base = "https://kaj-whatsapp-otp.example/v1/meta";

test("Meta's check gets the challenge back only with our token", async () => {
  const ok = await route(new Request(`${base}?hub.mode=subscribe&hub.verify_token=verify-me-0123456789&hub.challenge=4242`), env, fetch);
  assert.equal(ok.status, 200);
  assert.equal(await ok.text(), "4242");
  const bad = await route(new Request(`${base}?hub.mode=subscribe&hub.verify_token=nope&hub.challenge=4242`), env, fetch);
  assert.equal(bad.status, 403);
  const none = await route(new Request(`${base}?hub.mode=subscribe&hub.verify_token=x&hub.challenge=1`), {}, fetch);
  assert.equal(none.status, 403);
});

function signed(body, secret = env.META_APP_SECRET) {
  const sig = "sha256=" + createHmac("sha256", secret).update(body).digest("hex");
  return new Request(base, { method: "POST", body, headers: { "x-hub-signature-256": sig } });
}

const event = JSON.stringify({ object: "whatsapp_business_account", entry: [{ changes: [
  { field: "messages", value: { statuses: [{ status: "delivered", recipient_id: "22670000000" }, { status: "read" }] } },
  { field: "message_template_status_update", value: { event: "APPROVED", message_template_name: "mara_code" } },
] }] });

test("a signed event is taken, an unsigned or forged one refused", async () => {
  assert.equal((await route(signed(event), env, fetch)).status, 200);
  assert.equal((await route(signed(event, "other"), env, fetch)).status, 401);
  assert.equal((await route(new Request(base, { method: "POST", body: event }), env, fetch)).status, 401);
  assert.equal((await route(signed(event), {}, fetch)).status, 503);
});

test("the log counts, and never names a number", () => {
  const s = metaSummary(JSON.parse(event));
  assert.deepEqual(s.statuses, { delivered: 1, read: 1 });
  assert.deepEqual(s.templates, { "mara_code:APPROVED": 1 });
  assert.ok(!JSON.stringify(s).includes("22670000000"));
});
