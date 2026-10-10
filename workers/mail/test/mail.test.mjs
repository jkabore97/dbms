// workers/mail against a fake PostgREST and a fake Resend — no network.
//
//   node --test workers/mail/test
//
// The claims: the webhook's secret is required; only a welcome_emails
// INSERT (or a bare { user_id }) is taken; without RESEND_API_KEY nothing
// is claimed or sent and the log says why; a claimed row is sent once,
// from Mara, replying to KAJ, with the subject in the person's language,
// HTML and text, the user's id as Resend's Idempotency-Key, and the
// outcome written back; a row not pending is not sent; Resend's refusal
// and an unreachable Resend are written back as failed; the e-mail's
// words, links, colours and logo; a name cannot break the markup.

import assert from "node:assert/strict";
import { test } from "node:test";

import worker, { userIdOf, welcome } from "../src/index.js";
import { BRAND, LINKS, cleanName, welcomeEmail } from "../src/welcome.js";

const ID = "12412412-0000-0000-0000-000000000002";
const ENV = {
  SUPABASE_URL: "https://db.example.supabase.co",
  SUPABASE_SERVICE_ROLE_KEY: "service-key",
  MAIL_WEBHOOK_SECRET: "hook-secret",
  RESEND_API_KEY: "re_test_key",
  MAIL_FROM: "Mara <bienvenue@marakaj.com>",
  MAIL_REPLY_TO: "hello@kaj-consulting.com",
};

/// A fake PostgREST (the two RPCs) and a fake Resend, recording calls.
function fakes({ claim = { send: true, email: "awa@example.org", first_name: "Awa", lang: null },
                 resend = { status: 200, body: { id: "re_123" } },
                 resendThrows = false } = {}) {
  const calls = [];
  const logs = [];
  const fetch = async (url, init) => {
    const body = init && init.body ? JSON.parse(init.body) : null;
    calls.push({ url, headers: init.headers, body });
    if (url.endsWith("/rest/v1/rpc/welcome_email_claim")) {
      return new Response(JSON.stringify(claim), { status: 200 });
    }
    if (url.endsWith("/rest/v1/rpc/welcome_email_done")) {
      return new Response("true", { status: 200 });
    }
    if (url === "https://api.resend.com/emails") {
      if (resendThrows) throw new Error("connection reset");
      return new Response(JSON.stringify(resend.body), { status: resend.status });
    }
    throw new Error(`unexpected ${url}`);
  };
  return { calls, logs, io: { fetch, log: (m) => logs.push(m) } };
}

function hook(record, type = "INSERT", table = "welcome_emails") {
  return { type, table, schema: "public", record, old_record: null };
}

function post(body, secret = "hook-secret", path = "/v1/welcome") {
  return new Request(`https://kaj-mail.example.workers.dev${path}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${secret}`, "Content-Type": "application/json" },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

test("the door: a wrong or missing secret is 401, a bad body 400, another path 404", async () => {
  assert.equal((await worker.fetch(post(hook({ user_id: ID }), "nope"), ENV)).status, 401);
  assert.equal((await worker.fetch(post(hook({ user_id: ID }), ""), ENV)).status, 401);
  assert.equal((await worker.fetch(post(hook({ user_id: ID })), { ...ENV, MAIL_WEBHOOK_SECRET: "" })).status, 401);
  assert.equal((await worker.fetch(post("{not json"), ENV)).status, 400);
  assert.equal((await worker.fetch(post({}, "hook-secret", "/v1/other"), ENV)).status, 404);
});

test("only a welcome_emails INSERT, or a bare user_id, is taken", () => {
  assert.equal(userIdOf(hook({ user_id: ID })), ID);
  assert.equal(userIdOf({ user_id: ID.toUpperCase() }), ID);
  assert.equal(userIdOf(hook({ user_id: ID }, "UPDATE")), null);
  assert.equal(userIdOf(hook({ user_id: ID }, "INSERT", "notifications")), null);
  assert.equal(userIdOf(hook({ user_id: "not-a-uuid" })), null);
  assert.equal(userIdOf({}), null);
  assert.equal(userIdOf(null), null);
});

test("a webhook that is not ours is answered 200 and sends nothing", async () => {
  const res = await worker.fetch(post(hook({ recipient_id: ID }, "INSERT", "notifications")), ENV);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { skipped: "not a welcome_emails insert" });
});

test("without RESEND_API_KEY: nothing claimed, nothing sent, a clear log", async () => {
  const f = fakes();
  const out = await welcome(ID, { ...ENV, RESEND_API_KEY: "" }, f.io);
  assert.deepEqual(out, { skipped: "RESEND_API_KEY not set" });
  assert.equal(f.calls.length, 0, "the row is not claimed: it stays pending");
  assert.match(f.logs[0], /RESEND_API_KEY is not set/);
  assert.match(f.logs[0], new RegExp(ID));
});

test("a claimed row is sent once, from Mara, replying to KAJ, and written back", async () => {
  const f = fakes();
  const out = await welcome(ID, ENV, f.io);
  assert.deepEqual(out, { sent: true, id: "re_123" });
  assert.deepEqual(f.calls.map((c) => c.url.replace(ENV.SUPABASE_URL, "")), [
    "/rest/v1/rpc/welcome_email_claim",
    "https://api.resend.com/emails",
    "/rest/v1/rpc/welcome_email_done",
  ]);
  const [claim, send, done] = f.calls;
  assert.deepEqual(claim.body, { p_user: ID });
  assert.equal(claim.headers.Authorization, "Bearer service-key");
  assert.equal(claim.headers.apikey, "service-key");
  assert.equal(send.headers.Authorization, "Bearer re_test_key");
  assert.equal(send.headers["Idempotency-Key"], `welcome-${ID}`);
  assert.equal(send.body.from, "Mara <bienvenue@marakaj.com>");
  assert.equal(send.body.reply_to, "hello@kaj-consulting.com");
  assert.deepEqual(send.body.to, ["awa@example.org"]);
  assert.equal(send.body.subject, "Bienvenue sur Mara, Awa !");
  assert.match(send.body.html, /^<!DOCTYPE html>/);
  assert.match(send.body.text, /Ouvrir Mara : https:\/\/marakaj\.com/);
  assert.deepEqual(done.body, { p_user: ID, p_ok: true, p_id: "re_123", p_error: null });
});

test("the defaults hold without MAIL_FROM / MAIL_REPLY_TO", async () => {
  const f = fakes();
  await welcome(ID, { ...ENV, MAIL_FROM: undefined, MAIL_REPLY_TO: undefined }, f.io);
  const send = f.calls[1];
  assert.equal(send.body.from, "Mara <bienvenue@marakaj.com>");
  assert.equal(send.body.reply_to, "hello@kaj-consulting.com");
});

test("English when the account's language is English", async () => {
  const f = fakes({ claim: { send: true, email: "j@example.org", first_name: "John", lang: "en" } });
  await welcome(ID, ENV, f.io);
  assert.equal(f.calls[1].body.subject, "Welcome to Mara, John!");
  assert.match(f.calls[1].body.html, /Open Mara/);
});

test("a row that is not pending is not sent (never twice)", async () => {
  for (const reason of ["already sending", "already sent", "already failed", "switched off", "not asked"]) {
    const f = fakes({ claim: { send: false, reason } });
    const out = await welcome(ID, ENV, f.io);
    assert.deepEqual(out, { skipped: reason });
    assert.equal(f.calls.filter((c) => c.url.includes("resend")).length, 0, reason);
    assert.equal(f.calls.filter((c) => c.url.endsWith("welcome_email_done")).length, 0, reason);
  }
});

test("Resend's refusal is written back as failed, with its words", async () => {
  const f = fakes({ resend: { status: 403, body: { name: "validation_error", message: "The marakaj.com domain is not verified." } } });
  const out = await welcome(ID, ENV, f.io);
  assert.equal(out.sent, false);
  assert.match(out.error, /403.*not verified/);
  const done = f.calls.at(-1);
  assert.equal(done.body.p_ok, false);
  assert.match(done.body.p_error, /not verified/);
});

test("an unreachable Resend is written back as failed — not retried", async () => {
  const f = fakes({ resendThrows: true });
  const out = await welcome(ID, ENV, f.io);
  assert.equal(out.sent, false);
  assert.match(out.error, /unreachable: connection reset/);
  assert.equal(f.calls.at(-1).body.p_ok, false);
  assert.equal(f.calls.filter((c) => c.url.includes("resend")).length, 1);
});

test("the whole door, end to end", async () => {
  const f = fakes();
  const realFetch = globalThis.fetch;
  globalThis.fetch = f.io.fetch;
  try {
    const res = await worker.fetch(post(hook({ user_id: ID, status: "pending" })), ENV);
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { sent: true, id: "re_123" });
  } finally {
    globalThis.fetch = realFetch;
  }
});

test("the e-mail, in French: the words, the three steps, the links, the colours, the logo", () => {
  const m = welcomeEmail({ firstName: "Awa", lang: "fr" });
  assert.equal(m.subject, "Bienvenue sur Mara, Awa !");
  for (const s of ["Bienvenue sur Mara, Awa !", "Ajoutez vos articles", "Ouvrez votre vitrine",
                   "Faites votre première vente", "Ouvrir Mara",
                   "Une question ? Répondez simplement à cet e-mail.",
                   "Mara — Au Service du Peuple · KAJ Consulting LLC"]) {
    assert.ok(m.html.includes(s), s);
    assert.ok(m.text.includes(s), `text: ${s}`);
  }
  for (const href of [LINKS.app, LINKS.play, LINKS.privacy]) {
    assert.ok(m.html.includes(`href="${href}"`), href);
    assert.ok(m.text.includes(href), `text: ${href}`);
  }
  assert.equal(LINKS.logo, "https://marakaj.com/brand/mara-stacked.png");
  assert.ok(m.html.includes(`src="${LINKS.logo}"`));
  assert.ok(m.html.includes('alt="Mara"'));
  for (const colour of [BRAND.graphite, BRAND.caramel, BRAND.paper]) assert.ok(m.html.includes(colour), colour);
  assert.match(m.html, /<html lang="fr"/);
  assert.match(m.html, /max-width:560px/);
  assert.doesNotMatch(m.html, /<script|<link |<style/i, "inline styles only, nothing a client strips");
  assert.doesNotMatch(m.html, /Welcome to Mara/, "a known French reader gets no English line");
});

test("the e-mail, in English, equivalent", () => {
  const m = welcomeEmail({ firstName: "John", lang: "en" });
  assert.equal(m.subject, "Welcome to Mara, John!");
  for (const s of ["Welcome to Mara, John!", "Add your items", "Open your shop window",
                   "Make your first sale", "Open Mara", "A question? Just reply to this e-mail.",
                   "Mara — Au Service du Peuple · KAJ Consulting LLC"]) {
    assert.ok(m.html.includes(s), s);
  }
  assert.match(m.html, /<html lang="en"/);
  assert.match(m.text, /Open Mara: https:\/\/marakaj\.com/);
});

test("language unknown: French, with one short English line", () => {
  const m = welcomeEmail({ firstName: "Awa", lang: null });
  assert.equal(m.subject, "Bienvenue sur Mara, Awa !");
  assert.match(m.html, /Prefer English\? Reply to this e-mail/);
  assert.match(m.text, /Prefer English\?/);
  const odd = welcomeEmail({ firstName: "Awa", lang: "mos" });
  assert.match(odd.html, /Prefer English/);
});

test("no first name: a subject that still reads", () => {
  assert.equal(welcomeEmail({ firstName: "", lang: "fr" }).subject, "Bienvenue sur Mara !");
  assert.equal(welcomeEmail({ firstName: null, lang: "en" }).subject, "Welcome to Mara!");
  assert.equal(welcomeEmail({ firstName: "   ", lang: null }).subject, "Bienvenue sur Mara !");
});

test("a name cannot break the markup or the subject line", () => {
  const m = welcomeEmail({ firstName: '<img src=x onerror=alert(1)>"Bob\r\nBcc: x@y', lang: "fr" });
  assert.doesNotMatch(m.html, /<img src=x/);
  assert.doesNotMatch(m.subject, /[\r\n]/);
  assert.ok(cleanName("a".repeat(100)).length <= 40);
  assert.ok(m.html.includes("&quot;Bob"));
});
