// Plays Supabase and Meta against workers/whatsapp-otp — no network.
//
//   node --test workers/whatsapp-otp/test
//
// Supabase: the Send SMS hook's payload and its Standard Webhooks signature
// (computed here the way Supabase computes it). Meta: a fake fetch that
// records the message it was handed and answers as the Cloud API does.

import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import { test } from "node:test";

import {
  graphUrl, hookKey, hookTarget, hmacBase64, route, verifyHook, whatsappMessage,
} from "../src/index.js";

// A made-up hook secret, in the shape Supabase shows: « v1,whsec_<base64> ».
const KEY = "dGVzdC1rZXktb25seS1mb3ItdGhlc2UtdGVzdHM=";
const SECRET = `v1,whsec_${KEY}`;
const env = {
  WHATSAPP_TOKEN: "test-token",
  WHATSAPP_PHONE_ID: "1234567890",
  WHATSAPP_TEMPLATE: "mara_code",
  WHATSAPP_LANGUAGE: "fr",
  GRAPH_API_VERSION: "v23.0",
  SEND_SMS_HOOK_SECRET: SECRET,
};
const OTP = "482913";

function payload(overrides = {}) {
  return {
    user: { id: "u1", email: "awa@example.com", phone: "", new_phone: "22670123456", ...overrides.user },
    sms: { otp: OTP, phone: "22670123456", ...overrides.sms },
  };
}

/// A request signed as Supabase signs it.
async function signed(body, { secret = KEY, id = "msg_1", at = Math.floor(Date.now() / 1000), sig } = {}) {
  const raw = typeof body === "string" ? body : JSON.stringify(body);
  const mac = sig ?? await hmacBase64(hookKey(secret), `${id}.${at}.${raw}`);
  return new Request("https://otp.example/v1/send-sms", {
    method: "POST",
    headers: {
      "webhook-id": id,
      "webhook-timestamp": String(at),
      "webhook-signature": `v1,${mac}`,
      "Content-Type": "application/json",
    },
    body: raw,
  });
}

/// Meta, faked: records each call and answers [status, body].
function fakeMeta(status = 200, body = { messages: [{ id: "wamid.1" }] }) {
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({ url, headers: init.headers, body: JSON.parse(init.body) });
    return new Response(JSON.stringify(body), { status });
  };
  return { fetchImpl, calls };
}

/// Everything written to the console while [fn] runs.
async function captureConsole(fn) {
  const lines = [];
  const saved = {};
  for (const k of ["log", "info", "warn", "error", "debug"]) {
    saved[k] = console[k];
    console[k] = (...a) => lines.push(a.map(String).join(" "));
  }
  try {
    return { result: await fn(), lines };
  } finally {
    Object.assign(console, saved);
  }
}

test("the hook's signature: id, timestamp and body under the secret; stale, changed or foreign fails", async () => {
  const raw = JSON.stringify(payload());
  const at = 1_800_000_000;
  // Computed apart from the Worker, as the Standard Webhooks libraries do:
  // the key is what follows « whsec_ », base64-decoded.
  const mac = createHmac("sha256", Buffer.from(KEY, "base64"))
    .update(`msg_1.${at}.${raw}`).digest("base64");
  assert.equal(mac, await hmacBase64(hookKey(SECRET), `msg_1.${at}.${raw}`));
  const headers = (sig, id = "msg_1", ts = at) =>
    new Headers({ "webhook-id": id, "webhook-timestamp": String(ts), "webhook-signature": sig });
  assert.equal(await verifyHook(headers(`v1,${mac}`), raw, SECRET, at + 10), true);
  // Supabase joins one signature per secret with « , »: one good one is enough.
  assert.equal(await verifyHook(headers(`v1,AAAA, v1,${mac}`), raw, SECRET, at), true);
  assert.equal(await verifyHook(headers(`v1,${mac}`), raw + " ", SECRET, at), false, "a changed body fails");
  assert.equal(await verifyHook(headers(`v1,${mac}`, "msg_2"), raw, SECRET, at), false, "another id fails");
  assert.equal(await verifyHook(headers(`v1,${mac}`), raw, "v1,whsec_b3RoZXI=", at), false, "another secret fails");
  assert.equal(await verifyHook(headers(`v1,${mac}`), raw, SECRET, at + 301), false, "older than five minutes fails");
  assert.equal(await verifyHook(headers(`v2,${mac}`), raw, SECRET, at), false, "another scheme fails");
  assert.equal(await verifyHook(new Headers(), raw, SECRET, at), false, "no headers fails");
  // The secret's three spellings are one key.
  assert.deepEqual(hookKey(SECRET), hookKey(`whsec_${KEY}`));
  assert.deepEqual(hookKey(SECRET), hookKey(KEY));
  assert.equal(hookKey("v1,whsec_%%%"), null);
});

test("a signed hook sends the authentication template, the code in its body and its button, to the new number", async () => {
  const meta = fakeMeta();
  const res = await route(await signed(payload()), env, meta.fetchImpl);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), {});
  assert.equal(meta.calls.length, 1);
  const call = meta.calls[0];
  assert.equal(call.url, "https://graph.facebook.com/v23.0/1234567890/messages");
  assert.equal(call.headers.Authorization, "Bearer test-token");
  assert.deepEqual(call.body, whatsappMessage("22670123456", OTP, env));
  assert.equal(call.body.to, "22670123456");
  assert.equal(call.body.template.name, "mara_code");
  assert.equal(call.body.template.language.code, "fr");
  assert.deepEqual(call.body.template.components, [
    { type: "body", parameters: [{ type: "text", text: OTP }] },
    { type: "button", sub_type: "url", index: "0", parameters: [{ type: "text", text: OTP }] },
  ]);
});

test("where the code goes: the hook's number first, then the account's new number; a + and spaces dropped", () => {
  assert.equal(hookTarget(payload()).to, "22670123456");
  assert.equal(hookTarget(payload({ sms: { phone: "" }, user: { new_phone: "+226 70 99 88 77" } })).to, "22670998877");
  assert.equal(hookTarget(payload({ sms: { phone: undefined }, user: { new_phone: "", phone: "22671000000" } })).to, "22671000000");
  assert.equal(hookTarget(payload({ sms: { phone: "123" } })).status, 422);
  assert.equal(hookTarget(payload({ sms: { otp: "" } })).status, 400);
});

test("a phone-only sign-up (no e-mail) is refused and nothing is sent", async () => {
  const meta = fakeMeta();
  const res = await route(await signed(payload({ user: { email: "" } })), env, meta.fetchImpl);
  const body = await res.json();
  assert.equal(body.error.http_code, 403);
  assert.equal(meta.calls.length, 0);
});

test("a hook that is not Supabase's is refused before anything is sent", async () => {
  const meta = fakeMeta();
  const forged = await signed(payload(), { secret: "b3RoZXItc2VjcmV0" });
  assert.equal((await route(forged, env, meta.fetchImpl)).status, 401);
  const stale = await signed(payload(), { at: Math.floor(Date.now() / 1000) - 3600 });
  assert.equal((await route(stale, env, meta.fetchImpl)).status, 401);
  // No secret installed: nothing can be checked, nothing is sent.
  const res = await route(await signed(payload()), { ...env, SEND_SMS_HOOK_SECRET: "" }, meta.fetchImpl);
  assert.equal(res.status, 401);
  assert.equal(meta.calls.length, 0);
});

test("Meta's refusals come back as the hook's error, in words the shopper reads", async () => {
  const cases = [
    [400, { error: { code: 131030, message: "Recipient phone number not in allowed list" } }, 422],
    [400, { error: { code: 131026, message: "Message undeliverable" } }, 422],
    [429, { error: { code: 130429, message: "Rate limit hit" } }, 429],
    [400, { error: { code: 131056, message: "Pair rate limit hit" } }, 429],
    [401, { error: { code: 190, message: "Invalid OAuth access token" } }, 502],
    [500, "not json", 502],
  ];
  for (const [status, body, httpCode] of cases) {
    const meta = fakeMeta(status, body);
    const res = await route(await signed(payload()), env, meta.fetchImpl);
    assert.equal(res.status, 200, "Supabase reads the error from a 200");
    const out = await res.json();
    assert.equal(out.error.http_code, httpCode, `Meta ${status} → ${httpCode}`);
    assert.ok(out.error.message.length > 10);
  }
  // WhatsApp unreachable.
  const res = await route(await signed(payload()), env, async () => { throw new Error("offline"); });
  assert.equal((await res.json()).error.http_code, 502);
});

test("the code is never written to the console, sent or refused", async () => {
  const { lines } = await captureConsole(async () => {
    await route(await signed(payload()), env, fakeMeta().fetchImpl);
    await route(await signed(payload()), env, fakeMeta(400, { error: { code: 131030 } }).fetchImpl);
    await route(await signed(payload()), env, fakeMeta(500, "x").fetchImpl);
    await route(await signed(payload({ user: { email: "" } })), env, fakeMeta().fetchImpl);
  });
  const all = lines.join("\n");
  assert.ok(!all.includes(OTP), "the code was logged");
  assert.ok(!all.includes("70123456"), "the number was logged");
  assert.ok(!all.includes("test-token"), "the token was logged");
});

test("not set up yet: the hook says so, health says not ready and shows no value", async () => {
  const bare = { SEND_SMS_HOOK_SECRET: SECRET };
  const meta = fakeMeta();
  const res = await route(await signed(payload()), bare, meta.fetchImpl);
  assert.equal((await res.json()).error.http_code, 503);
  assert.equal(meta.calls.length, 0);
  const health = await route(new Request("https://otp.example/v1/health"), bare, meta.fetchImpl);
  assert.deepEqual(await health.json(), { ready: false });
  const full = await route(new Request("https://otp.example/v1/health"), env, meta.fetchImpl);
  const text = await full.text();
  assert.deepEqual(JSON.parse(text), { ready: true });
  for (const v of Object.values(env)) {
    if (v.length > 4) assert.ok(!text.includes(v), "health shows a value");
  }
});

test("only the two doors", async () => {
  const meta = fakeMeta();
  assert.equal((await route(new Request("https://otp.example/v1/send-sms"), env, meta.fetchImpl)).status, 405);
  assert.equal((await route(new Request("https://otp.example/"), env, meta.fetchImpl)).status, 404);
  assert.equal(graphUrl({ WHATSAPP_PHONE_ID: "99" }), "https://graph.facebook.com/v23.0/99/messages");
});
