// « Aide Mara » (src/help.js): the page the App Store's Support URL points
// to, with the platform's contacts read live, and the addresses that lead
// to it.
//
//   node --test workers/kaj-app/test/*.test.mjs
//
// Supabase is played by a stub of fetch: what support_contacts() answers,
// or a failure.

import assert from "node:assert/strict";
import { afterEach, test } from "node:test";

import site from "../src/index.js";
import { FAQ, forgetSupportContacts, supportContacts } from "../src/help.js";

const PAGE = "<!DOCTYPE html><html><head><title>Mara</title></head><body></body></html>";
const env = {
  SUPABASE_URL: "https://db.example.supabase.co",
  SUPABASE_PUBLISHABLE_KEY: "sb_publishable_test",
  ASSETS: { async fetch() { return new Response(PAGE, { headers: { "Content-Type": "text/html" } }); } },
};
const realFetch = globalThis.fetch;
const asked = [];

function supabase(answer) {
  globalThis.fetch = async (url, init) => {
    asked.push({ url: String(url), init });
    if (answer instanceof Error) throw answer;
    if (typeof answer === "number") return new Response("{}", { status: answer });
    return new Response(JSON.stringify(answer), { headers: { "Content-Type": "application/json" } });
  };
}

afterEach(() => {
  globalThis.fetch = realFetch;
  asked.length = 0;
  forgetSupportContacts();
});

const get = (path, e = env) => site.fetch(new Request(`https://marakaj.com${path}`), e);

test("with a number: WhatsApp with the greeting, the e-mail, the hours, the FAQ, the links", async () => {
  supabase({ email: "hello@kaj-consulting.com", whatsapp: "18623354492", hours: "24 h/24, 7 j/7" });
  const r = await get("/aide");
  assert.equal(r.status, 200);
  assert.match(r.headers.get("Content-Type"), /^text\/html/);
  assert.equal(r.headers.get("Cache-Control"), "public, max-age=60");
  assert.equal(r.headers.get("X-Content-Type-Options"), "nosniff");
  const html = await r.text();
  assert.match(html, /<title>Aide Mara · Mara<\/title>/);
  assert.match(html, /<h1>Aide Mara<\/h1>/);
  assert.match(html, /Une question, un souci \? Nous répondons 24 h\/24, 7 j\/7\./);
  assert.match(html, /We answer 24\/7\./);
  assert.ok(html.includes(
    `href="https://wa.me/18623354492?text=${encodeURIComponent("Bonjour, j'ai besoin d'aide avec Mara.")}"`));
  assert.ok(html.includes('href="mailto:hello@kaj-consulting.com"'));
  for (const [q, a, qEn, aEn] of FAQ) {
    for (const t of [q, a, qEn, aEn]) {
      assert.ok(html.includes(t.replace(/&/g, "&amp;").replace(/"/g, "&quot;")), t);
    }
  }
  assert.ok(FAQ.length >= 5 && FAQ.length <= 6);
  for (const href of ["/confidentialite", "/conditions", "/supprimer-mon-compte"]) {
    assert.ok(html.includes(`href="${href}"`), href);
  }
  assert.match(html, /Mara est édité par KAJ Consulting LLC/);
  assert.match(html, /<meta property="og:title" content="Aide Mara">/);
  assert.match(html, /<meta property="og:url" content="https:\/\/marakaj.com\/aide">/);
  assert.match(html, /<meta name="description" content="[^"]+et sur WhatsApp\.">/);
  assert.doesNotMatch(html, /<script/i, "no JavaScript needed");
  // Asked as the street (the publishable key), once.
  assert.equal(asked.length, 1);
  assert.equal(asked[0].url, "https://db.example.supabase.co/rest/v1/rpc/support_contacts");
  assert.equal(asked[0].init.headers.apikey, "sb_publishable_test");
});

test("without a number: no WhatsApp button; the hours the platform set", async () => {
  supabase({ email: "aide@marakaj.com", whatsapp: null, hours: "du lundi au samedi, 8 h – 20 h" });
  const html = await (await get("/aide")).text();
  assert.doesNotMatch(html, /wa\.me/);
  assert.doesNotMatch(html, /WhatsApp<\/a>/);
  assert.ok(html.includes('href="mailto:aide@marakaj.com"'));
  assert.match(html, /Nous répondons du lundi au samedi, 8 h – 20 h\./);
  assert.match(html, /We answer du lundi au samedi, 8 h – 20 h\./);
  assert.match(html, /Write to us by e-mail\./);
});

test("the RPC failing: the e-mail and hours as installed, no WhatsApp — never a 500", async () => {
  for (const failure of [new Error("connect ECONNREFUSED"), 500, 404, "not an object", [1, 2]]) {
    forgetSupportContacts();
    supabase(failure);
    const r = await get("/aide");
    assert.equal(r.status, 200, String(failure));
    const html = await r.text();
    assert.ok(html.includes('href="mailto:hello@kaj-consulting.com"'), String(failure));
    assert.match(html, /Nous répondons 24 h\/24, 7 j\/7\./);
    assert.doesNotMatch(html, /wa\.me/, String(failure));
  }
  // No Supabase configured at all: the same.
  const html = await (await get("/aide", { ASSETS: env.ASSETS })).text();
  assert.ok(html.includes('href="mailto:hello@kaj-consulting.com"'));
});

test("a wrong value is never drawn: a number that is not digits, an address that is not one", async () => {
  supabase({ email: "pas une adresse", whatsapp: "+226 70 00", hours: "x".repeat(61) });
  const html = await (await get("/aide")).text();
  assert.doesNotMatch(html, /wa\.me/);
  assert.ok(html.includes('href="mailto:hello@kaj-consulting.com"'));
  assert.match(html, /Nous répondons 24 h\/24, 7 j\/7\./);
});

test("the values are written as text, never as HTML", async () => {
  supabase({ email: 'a"b@x.io', whatsapp: "22670000000", hours: '<script>alert("x")</script> & co' });
  const html = await (await get("/aide")).text();
  assert.doesNotMatch(html, /<script>alert/);
  assert.ok(html.includes("&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt; &amp; co"));
  assert.ok(html.includes('href="mailto:a&quot;b@x.io"'));
  assert.doesNotMatch(html, /href="mailto:a"b/);
});

test("kept a minute: a burst of visits asks Supabase once, then again after", async () => {
  supabase({ email: "hello@kaj-consulting.com", whatsapp: "18623354492", hours: "24 h/24, 7 j/7" });
  const t0 = 1_000_000;
  await supportContacts(env, t0);
  await supportContacts(env, t0 + 30_000);
  assert.equal(asked.length, 1);
  await supportContacts(env, t0 + 61_000);
  assert.equal(asked.length, 2);
});

test("/support, /support/ and /aide/ are sent to /aide for good", async () => {
  for (const path of ["/support", "/support/", "/aide/", "/support?from=apple"]) {
    const r = await get(path);
    assert.equal(r.status, 301, path);
    const to = path.includes("?") ? "https://marakaj.com/aide?from=apple" : "https://marakaj.com/aide";
    assert.equal(r.headers.get("Location"), to, path);
  }
  // The old address goes to marakaj.com first, the same path.
  const old = await site.fetch(new Request("https://dbms.kabore-boss.workers.dev/support"), env);
  assert.equal(old.headers.get("Location"), "https://marakaj.com/support");
});

test("every plain page's footer leads to « Aide »", async () => {
  for (const path of ["/confidentialite", "/conditions", "/supprimer-mon-compte"]) {
    const html = await (await get(path)).text();
    assert.ok(html.includes('<a href="/aide">Aide</a>'), path);
  }
  supabase(500);
  assert.ok((await (await get("/aide")).text()).includes('<a href="/aide">Aide</a>'));
});
