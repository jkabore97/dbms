// Studio's writing assistant (173): Marakaj Pro, the card's edit token as
// the key, the server's allowance asked first, Claude's text handed back.

import assert from "node:assert/strict";
import { test } from "node:test";

import { assistant } from "../src/assistant.js";

const TOKEN = "ed17ed17ed17ed17ed17ed17";
const env = { SUPABASE_URL: "https://x.supabase.co", SUPABASE_PUBLISHABLE_KEY: "sb_publishable_test", ANTHROPIC_API_KEY: "test-key" };
let allowanceAnswer = { status: 200, body: { pro: true, left: 39 } };
const asked = [];
globalThis.fetch = async (url, init) => {
  asked.push({ url: String(url), body: init && init.body ? JSON.parse(init.body) : null });
  return new Response(JSON.stringify(allowanceAnswer.body), { status: allowanceAnswer.status, headers: { "Content-Type": "application/json" } });
};
const fakeClient = (reply) => {
  const sent = [];
  return {
    sent,
    beta: { messages: { create: async (params) => { sent.push(params); return reply; } } },
  };
};
const post = (body) => new Request("https://marakaj.com/api/assistant", { method: "POST", body: JSON.stringify(body) });
const ask = { slug: "awa-et-paul-ab12", edit: TOKEN, kind: "mariage", title: "Awa & Paul", place: "Ouagadougou", block: "text", what: "ecrire" };

test("written by Claude for a Pro card: the allowance asked first, the request's shape, the text back", async () => {
  allowanceAnswer = { status: 200, body: { pro: true, left: 39 } };
  asked.length = 0;
  const c = fakeClient({ stop_reason: "end_turn", content: [{ type: "text", text: "« Nous avons la joie de vous inviter. »" }] });
  const r = await assistant(post(ask), env, { client: c });
  assert.equal(r.status, 200);
  const j = await r.json();
  assert.equal(j.text, "Nous avons la joie de vous inviter.", "the quotes around it taken off");
  assert.equal(j.left, 39);
  assert.equal(asked[0].url, "https://x.supabase.co/rest/v1/rpc/event_assist_use");
  assert.deepEqual(asked[0].body, { p_slug: "awa-et-paul-ab12", p_edit: TOKEN });
  const p = c.sent[0];
  assert.equal(p.model, "claude-opus-5-5");
  assert.deepEqual(p.output_config, { effort: "low" });
  assert.equal(p.fallbacks, "default");
  assert.deepEqual(p.betas, ["server-side-fallback-2026-07-01"]);
  assert.ok(p.system.includes("N’invente aucun fait"));
  assert.ok(p.messages[0].content.includes("Événement : mariage") && p.messages[0].content.includes("Lieu : Ouagadougou"));
});

test("refused plainly: no key, not Pro, the day's forty used, a wrong token, nothing to rewrite, Claude declining", async () => {
  let r = await assistant(post(ask), { ...env, ANTHROPIC_API_KEY: "" });
  assert.equal(r.status, 503);
  assert.match((await r.json()).error, /pas disponible/);

  allowanceAnswer = { status: 200, body: { pro: false, left: 0 } };
  const c = fakeClient({ stop_reason: "end_turn", content: [{ type: "text", text: "x" }] });
  r = await assistant(post(ask), env, { client: c });
  assert.equal(r.status, 402);
  assert.equal(c.sent.length, 0, "Claude not asked for a free business");

  allowanceAnswer = { status: 400, body: { message: "L'assistant a assez écrit pour aujourd'hui : il revient demain." } };
  r = await assistant(post(ask), env, { client: c });
  assert.equal(r.status, 429);

  r = await assistant(post({ ...ask, edit: "short" }), env, { client: c });
  assert.equal(r.status, 403);

  allowanceAnswer = { status: 200, body: { pro: true, left: 3 } };
  r = await assistant(post({ ...ask, what: "raccourcir", text: "" }), env, { client: c });
  assert.equal(r.status, 400);
  assert.equal(c.sent.length, 0);

  const no = fakeClient({ stop_reason: "refusal", content: [] });
  r = await assistant(post(ask), env, { client: no });
  assert.equal(r.status, 422);

  r = await assistant(new Request("https://marakaj.com/api/assistant"), env, { client: c });
  assert.equal(r.status, 405);
});
