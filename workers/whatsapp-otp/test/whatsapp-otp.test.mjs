// Plays Supabase and Meta against workers/whatsapp-otp — no network.
//
//   node --test workers/whatsapp-otp/test
//
// Supabase: the Send SMS hook's payload and its Standard Webhooks signature
// (computed here the way Supabase computes it). Meta: a fake fetch that
// records the message it was handed and answers as the Cloud API does.

import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import { beforeEach, test } from "node:test";

import {
  LIMITS, graphUrl, hookKey, hookTarget, hmacBase64, memoryAllow, otpGate, resetMemoryLimits, route,
  verifyHook, whatsappMessage,
} from "../src/index.js";

// Each test starts with a fresh isolate's ration (130).
beforeEach(() => resetMemoryLimits());

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
    resetMemoryLimits(); // Meta's words, not the ration (130), are tried here.
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

// ----------------------------------------------------------------
// The ration (130, SEC_AUDIT_2 M6)
// ----------------------------------------------------------------

const USER = "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b";

/// Meta and Supabase, faked together: the ration's answer for each call
/// (or a status), and every call recorded.
function fakeBoth(rationAnswers) {
  const meta = [];
  const ration = [];
  const fetchImpl = async (url, init) => {
    if (String(url).includes("/rest/v1/rpc/otp_send_allow")) {
      ration.push({ url, headers: init.headers, body: JSON.parse(init.body) });
      const next = rationAnswers.length > 1 ? rationAnswers.shift() : rationAnswers[0];
      if (next instanceof Error) throw next;
      if (typeof next === "number") return new Response("{}", { status: next });
      return new Response(JSON.stringify(next), { status: 200 });
    }
    meta.push({ url, body: JSON.parse(init.body) });
    return new Response(JSON.stringify({ messages: [{ id: "wamid.1" }] }), { status: 200 });
  };
  return { fetchImpl, meta, ration };
}

const withDb = { ...env, SUPABASE_URL: "https://proj.supabase.co/", SUPABASE_SERVICE_ROLE_KEY: "service-role-test-key" };

test("the ration in memory: a 4th code to one number in 10 minutes is refused quietly, nothing sent", async () => {
  const meta = fakeMeta();
  for (let i = 0; i < LIMITS.phonePer10Minutes; i++) {
    const res = await route(await signed(payload({ user: { id: USER } }), { id: `m${i}` }), env, meta.fetchImpl);
    assert.deepEqual(await res.json(), {}, `code ${i + 1} sent`);
  }
  const { result, lines } = await captureConsole(async () =>
    route(await signed(payload({ user: { id: USER } }), { id: "m4" }), env, meta.fetchImpl));
  const out = await result.json();
  assert.equal(result.status, 200, "Supabase reads the refusal from a 200");
  assert.equal(out.error.http_code, 429);
  assert.equal(out.error.message, "Trop de codes envoyés. Réessayez plus tard.");
  assert.equal(meta.calls.length, LIMITS.phonePer10Minutes, "nothing sent over the limit");
  const all = lines.join("\n");
  assert.ok(all.includes("phone_10_minutes"));
  assert.ok(!all.includes("70123456") && !all.includes(OTP), "the log names neither the number nor the code");
  // Another number, the same account: still free.
  const other = await route(await signed(payload({ user: { id: USER }, sms: { phone: "22670999999" } }), { id: "m5" }),
    env, meta.fetchImpl);
  assert.deepEqual(await other.json(), {});
});

test("the ration in memory: windows of 10 minutes and a day, per number and per account", () => {
  const t0 = Date.UTC(2026, 9, 12, 8, 0, 0);
  const min = 60 * 1000;
  // Per number: 3 in 10 minutes, 10 a day.
  let sent = 0;
  for (let i = 0; i < 30; i++) {
    if (memoryAllow("22670000001", null, t0 + i * 4 * min).ok) sent++;
  }
  assert.equal(sent, LIMITS.phonePerDay, "ten a day, however spread");
  assert.equal(memoryAllow("22670000001", null, t0 + 25 * 60 * min).ok, true, "a day later, again");
  resetMemoryLimits();
  // Per account: 5 in 10 minutes across numbers, 20 a day.
  const results = [];
  for (let i = 0; i < 6; i++) results.push(memoryAllow(`2267100000${i}`, USER, t0 + i * 1000).ok);
  assert.deepEqual(results, [true, true, true, true, true, false]);
  assert.equal(memoryAllow("22671000009", USER, t0 + 2000).reason, "account_10_minutes");
  let day = 5;
  for (let i = 0; i < 40; i++) {
    if (memoryAllow(`22672${String(i).padStart(6, "0")}`, USER, t0 + (11 + i * 11) * min).ok) day++;
  }
  assert.equal(day, LIMITS.accountPerDay);
  assert.equal(memoryAllow("22673000000", USER, t0 + 23 * 60 * min).reason, "account_day");
});

test("the database decides when it can be asked: the number's digits and the account, as the service role", async () => {
  const both = fakeBoth([{ ok: true }]);
  const res = await route(await signed(payload({ user: { id: USER } })), withDb, both.fetchImpl);
  assert.deepEqual(await res.json(), {});
  assert.equal(both.ration.length, 1);
  assert.equal(both.ration[0].url, "https://proj.supabase.co/rest/v1/rpc/otp_send_allow");
  assert.deepEqual(both.ration[0].body, { p_phone: "22670123456", p_user: USER });
  assert.equal(both.ration[0].headers.Authorization, "Bearer service-role-test-key");
  assert.equal(both.meta.length, 1, "sent");
  // Its no: refused, nothing sent — even where memory would say yes.
  const no = fakeBoth([{ ok: false, reason: "phone_day" }]);
  const { result, lines } = await captureConsole(async () =>
    route(await signed(payload({ user: { id: USER } }), { id: "d2" }), withDb, no.fetchImpl));
  const out = await result.json();
  assert.equal(out.error.http_code, 429);
  assert.equal(no.meta.length, 0);
  assert.ok(lines.join("\n").includes("phone_day, database"));
  assert.ok(!lines.join("\n").includes("service-role-test-key"));
  // An account id that is not a UUID is not passed on.
  const odd = fakeBoth([{ ok: true }]);
  await route(await signed(payload({ user: { id: "u1" } }), { id: "d3" }), withDb, odd.fetchImpl);
  assert.equal(odd.ration[0].body.p_user, null);
});

test("without the database's answer (130 not applied, an error, no answer) memory counts the same limits", async () => {
  for (const answer of [404, 500, new Error("offline"), { unexpected: true }]) {
    resetMemoryLimits();
    const both = fakeBoth([answer]);
    const codes = [];
    for (let i = 0; i < LIMITS.phonePer10Minutes + 1; i++) {
      const { result } = await captureConsole(async () =>
        route(await signed(payload({ user: { id: USER } }), { id: `f${i}` }), withDb, both.fetchImpl));
      const body = await result.json();
      codes.push(body.error?.http_code ?? 200);
    }
    assert.deepEqual(codes, [200, 200, 200, 429], `ration answered ${answer}`);
    assert.equal(both.meta.length, LIMITS.phonePer10Minutes);
  }
  // Asked directly: who counted.
  resetMemoryLimits();
  assert.equal((await otpGate({}, null, "22670123456", async () => { throw new Error("never"); })).by, "memory");
  assert.equal((await otpGate(withDb, null, "22670123456", fakeBoth([{ ok: true }]).fetchImpl)).by, "database");
});
