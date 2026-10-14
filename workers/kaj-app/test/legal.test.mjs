// The legal pages (src/legal.js), batch 147: the new Conditions
// d'utilisation name the platform's support e-mail, read live as /aide
// reads it; ?lang=en serves the faithful English under the note that the
// French binds; the deletion page stays French.
//
//   node --test workers/kaj-app/test/*.test.mjs

import assert from "node:assert/strict";
import { afterEach, test } from "node:test";

import site from "../src/index.js";
import { forgetSupportContacts } from "../src/help.js";
import { EN_PRIVACY, EN_TERMS, PRIVACY, TERMS, isLegalPath, legalPage } from "../src/legal.js";

const env = {
  SUPABASE_URL: "https://db.example.supabase.co",
  SUPABASE_PUBLISHABLE_KEY: "sb_publishable_test",
  ASSETS: { async fetch() { return new Response("app", { headers: { "Content-Type": "text/html" } }); } },
};
const realFetch = globalThis.fetch;

function supabase(answer) {
  globalThis.fetch = async () => {
    if (answer instanceof Error) throw answer;
    return new Response(JSON.stringify(answer), { headers: { "Content-Type": "application/json" } });
  };
}

afterEach(() => {
  globalThis.fetch = realFetch;
  forgetSupportContacts();
});

const get = (path) => site.fetch(new Request(`https://marakaj.com${path}`), env);

test("the terms name KAJ Consulting LLC, the version and the platform's e-mail, read live", async () => {
  supabase({ email: "aide@marakaj.com", whatsapp: null, hours: "8 h – 20 h" });
  const res = await get("/conditions");
  assert.equal(res.status, 200);
  const html = await res.text();
  assert.match(html, /<html lang="fr">/);
  assert.match(html, /exploité par KAJ Consulting LLC/);
  assert.match(html, /Version 2 — en vigueur le 14 octobre 2026\./);
  assert.match(html, /écrivez à aide@marakaj\.com/);
  assert.doesNotMatch(html, /\{email\}/);
  assert.match(html, /\[à valider par un avocat\]/);
  assert.match(html, /href="\/conditions\?lang=en"/);
});

test("Supabase down: the installed e-mail, never a 500", async () => {
  supabase(new Error("down"));
  const html = await (await get("/conditions")).text();
  assert.match(html, /hello@kaj-consulting\.com/);
  assert.doesNotMatch(html, /\{email\}/);
});

test("?lang=en: the English, the French binding, a way back to the French", async () => {
  supabase({ email: "aide@marakaj.com" });
  const html = await (await get("/conditions?lang=en")).text();
  assert.match(html, /<html lang="en">/);
  assert.match(html, /<h1>Terms of Use<\/h1>/);
  assert.match(html, /The French version of this text is the binding one/);
  assert.match(html, /run by KAJ Consulting LLC/);
  assert.match(html, /write to aide@marakaj\.com/);
  assert.match(html, /href="\/conditions" lang="fr"/);
  const privacy = await (await get("/confidentialite?lang=en")).text();
  assert.match(privacy, /<h1>Privacy Policy<\/h1>/);
  assert.match(privacy, /Checks against fraud/);
});

test("every French paragraph has its English at the same place", () => {
  assert.equal(EN_TERMS.blocks.length, TERMS.blocks.length);
  assert.equal(EN_PRIVACY.blocks.length, PRIVACY.blocks.length);
  TERMS.blocks.forEach((b, i) => assert.equal(b.startsWith("# "), EN_TERMS.blocks[i].startsWith("# "), b));
  PRIVACY.blocks.forEach((b, i) => assert.equal(b.startsWith("# "), EN_PRIVACY.blocks[i].startsWith("# "), b));
});

test("the deletion page has no English twin and stays French; other paths are not legal pages", async () => {
  const html = legalPage("/supprimer-mon-compte", { lang: "en" });
  assert.match(await html.text(), /<html lang="fr">/);
  assert.equal(isLegalPath("/conditions/"), true);
  assert.equal(isLegalPath("/aide"), false);
  assert.equal(legalPage("/nulle-part"), null);
});

test("an odd e-mail value is never written as « undefined »", async () => {
  const html = await legalPage("/conditions", { email: undefined }).text();
  assert.match(html, /hello@kaj-consulting\.com/);
});
