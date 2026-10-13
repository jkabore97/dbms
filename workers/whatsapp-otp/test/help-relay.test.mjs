// « Besoin d'aide » (133): the trainers' WhatsApp alert, against a fake
// PostgREST and a fake Meta — no network.
//
//   node --test workers/whatsapp-otp/test
//
// The database queues one outbox row per trainer to alert, with the
// template the platform set (help_whatsapp_template, default
// « aide_demande »); an empty setting queues nothing. The Worker claims
// the rows (help_whatsapp_claim, service role), sends each, and says how
// it went (help_whatsapp_done).

import assert from "node:assert/strict";
import { test } from "node:test";

import {
  helpMessage, helpParam, helpReady, helpRefusal, helpRelay, route, sendHelp,
} from "../src/index.js";

const ID = "6f1c2a9e-1b2c-4d5e-8f90-123456789abc";
const env = {
  WHATSAPP_TOKEN: "test-token",
  WHATSAPP_PHONE_ID: "1234567890",
  WHATSAPP_TEMPLATE: "mara_code",
  WHATSAPP_LANGUAGE: "fr",
  GRAPH_API_VERSION: "v23.0",
  SUPABASE_URL: "https://db.example",
  SUPABASE_SERVICE_ROLE_KEY: "service-key-for-tests",
};

function row(overrides = {}) {
  return {
    id: "00000000-0000-0000-0000-000000000001",
    to: "22670123456",
    template: "aide_demande",
    params: { name: "Salon Belle Vie", kind: "Boutique", subject: "Ventes", request_id: ID },
    ...overrides,
  };
}

/// PostgREST and Meta, faked: [rows] is what the claim answers; Meta
/// answers [metaStatus, metaBody]. Every call is recorded.
function fakeWorld({ rows = [row()], claimStatus = 200, metaStatus = 200, metaBody = { messages: [{ id: "wamid.1" }] } } = {}) {
  const calls = { claim: [], done: [], meta: [] };
  const fetchImpl = async (url, init) => {
    const u = String(url);
    const body = JSON.parse(init.body);
    if (u.endsWith("/rest/v1/rpc/help_whatsapp_claim")) {
      calls.claim.push({ headers: init.headers, body });
      return new Response(JSON.stringify(rows), { status: claimStatus });
    }
    if (u.endsWith("/rest/v1/rpc/help_whatsapp_done")) {
      calls.done.push(body);
      return new Response("", { status: 204 });
    }
    if (u.startsWith("https://graph.facebook.com/")) {
      calls.meta.push({ url: u, headers: init.headers, body });
      return new Response(JSON.stringify(metaBody), { status: metaStatus });
    }
    throw new Error(`unexpected call ${u}`);
  };
  return { fetchImpl, calls };
}

test("template on: the row is sent with the template, its three words and the link's id, then said sent", async () => {
  const w = fakeWorld();
  const r = await helpRelay(env, w.fetchImpl);
  assert.deepEqual(r, { sent: 1, failed: 0 });
  // Claimed with the service role, never anything else.
  assert.equal(w.calls.claim.length, 1);
  assert.equal(w.calls.claim[0].headers.Authorization, "Bearer service-key-for-tests");
  assert.deepEqual(w.calls.claim[0].body, { p_limit: 20 });
  // Meta: the template the row names (not the code's), in French.
  assert.equal(w.calls.meta.length, 1);
  const m = w.calls.meta[0];
  assert.equal(m.url, "https://graph.facebook.com/v23.0/1234567890/messages");
  assert.equal(m.headers.Authorization, "Bearer test-token");
  assert.equal(m.body.to, "22670123456");
  assert.equal(m.body.template.name, "aide_demande");
  assert.equal(m.body.template.language.code, "fr");
  assert.deepEqual(m.body.template.components[0].parameters.map((p) => p.text),
    ["Salon Belle Vie", "Boutique", "Ventes"]);
  assert.deepEqual(m.body.template.components[1],
    { type: "button", sub_type: "url", index: "0", parameters: [{ type: "text", text: ID }] });
  // And said.
  assert.deepEqual(w.calls.done, [{ p_id: row().id, p_ok: true, p_error: null }]);
});

test("template off: the database queues nothing, so nothing goes to Meta", async () => {
  const w = fakeWorld({ rows: [] });
  const r = await helpRelay(env, w.fetchImpl);
  assert.deepEqual(r, { sent: 0, failed: 0 });
  assert.equal(w.calls.meta.length, 0);
  assert.equal(w.calls.done.length, 0);
});

test("a row without a template is never sent, and is said « off »", async () => {
  const w = fakeWorld({ rows: [row({ template: "" })] });
  const r = await helpRelay(env, w.fetchImpl);
  assert.deepEqual(r, { sent: 0, failed: 1 });
  assert.equal(w.calls.meta.length, 0);
  assert.deepEqual(w.calls.done, [{ p_id: row().id, p_ok: false, p_error: "off" }]);
});

test("a template Meta has not approved: said « template », for the console", async () => {
  const w = fakeWorld({ metaStatus: 404, metaBody: { error: { code: 132001, message: "Template name does not exist" } } });
  const r = await helpRelay(env, w.fetchImpl);
  assert.deepEqual(r, { sent: 0, failed: 1 });
  assert.deepEqual(w.calls.done, [{ p_id: row().id, p_ok: false, p_error: "template" }]);
});

test("Meta's other refusals in one word; a network failure too", async () => {
  assert.equal(helpRefusal(400, 131026), "not_whatsapp");
  assert.equal(helpRefusal(429, null), "rate");
  assert.equal(helpRefusal(400, 132015), "template");
  assert.equal(helpRefusal(500, 1), "meta");
  const down = async (url) => {
    if (String(url).startsWith("https://graph.facebook.com/")) throw new Error("offline");
    return new Response("", { status: 204 });
  };
  assert.equal(await sendHelp(row(), env, down), "network");
});

test("not set up: without the database's two nothing is asked; without Meta's two nothing is claimed", async () => {
  const w = fakeWorld();
  assert.deepEqual(await helpRelay({ ...env, SUPABASE_SERVICE_ROLE_KEY: "" }, w.fetchImpl), { skipped: "no database" });
  assert.deepEqual(await helpRelay({ ...env, WHATSAPP_TOKEN: "" }, w.fetchImpl), { skipped: "no whatsapp" });
  assert.equal(w.calls.claim.length, 0);
  assert.equal(w.calls.meta.length, 0);
  assert.equal(helpReady(env), true);
  assert.equal(helpReady({ ...env, WHATSAPP_PHONE_ID: "" }), false);
});

test("a database without 133 (the claim is 404): skipped, nothing sent", async () => {
  const w = fakeWorld({ claimStatus: 404 });
  assert.deepEqual(await helpRelay(env, w.fetchImpl), { skipped: "no help" });
  assert.equal(w.calls.meta.length, 0);
});

test("the words are plain on one line, 60 characters at most; a bad id never makes a link", () => {
  assert.equal(helpParam("Salon\n\tBelle    Vie​"), "Salon Belle Vie");
  assert.equal(helpParam(""), "—");
  assert.equal(helpParam("x".repeat(80)).length, 60);
  const m = helpMessage(row({ params: { name: "A", kind: "Ferme", subject: "Bandes", request_id: "../../evil" } }), env);
  assert.equal(m.template.components[1].parameters[0].text, "");
});

test("GET /v1/help/health says whether the relay can work, never a value", async () => {
  const res = await route(new Request("https://otp.example/v1/help/health"), env, async () => {
    throw new Error("no network");
  });
  const text = await res.text();
  assert.deepEqual(JSON.parse(text), { help: true });
  for (const v of Object.values(env)) {
    if (v.length > 4) assert.ok(!text.includes(v), "health shows a value");
  }
});

test("nothing logged names the number, the business or the request", async () => {
  const lines = [];
  const saved = console.log;
  console.log = (...a) => lines.push(a.join(" "));
  try {
    const w = fakeWorld({ metaStatus: 400, metaBody: { error: { code: 131026 } } });
    await helpRelay(env, w.fetchImpl);
  } finally {
    console.log = saved;
  }
  const all = lines.join("\n");
  for (const secret of ["22670123456", "Salon Belle Vie", ID, "test-token", "service-key-for-tests"]) {
    assert.ok(!all.includes(secret), `the log names ${secret}`);
  }
});
