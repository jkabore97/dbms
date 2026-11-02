// /e/<slug> — an event's card (152): the card's page under /cartes with the
// event written into it, never cached; nothing when the server says so.
//
//   node --test workers/kaj-app/test/*.test.mjs

import assert from "node:assert/strict";
import { test } from "node:test";

import site from "../src/index.js";

const PAGE = "<!DOCTYPE html><html><head><title>Marakaj</title></head><body></body></html>";
const CARD = '<!doctype html><html lang="fr"><head><meta charset="utf-8"><title>Inès & Thomas</title>'
  + '<link rel="stylesheet" href="shared.css"></head><body><article class="card"><h1 data-edit="names">Inès</h1>'
  + '<a href="#rsvp">RSVP</a></article><script src="shared.js"></script></body></html>';
const ANIME = '<!doctype html><html lang="fr"><head><meta charset="utf-8"><title>Marakaj Événements</title></head>'
  + '<body><main id="site"></main><script>var S = {};</script></body></html>';
const files = {
  "/index.html": [PAGE, "text/html; charset=utf-8"],
  "/cartes/come.html": [CARD, "text/html; charset=utf-8"],
  "/cartes/gala.html": [CARD.replaceAll("Inès", "Gala"), "text/html; charset=utf-8"],
  "/cartes/shared.css": ["body{}", "text/css"],
  "/evenements/index.html": [ANIME, "text/html; charset=utf-8"],
};
const env = {
  SUPABASE_URL: "https://x.supabase.co",
  SUPABASE_PUBLISHABLE_KEY: "sb_publishable_test",
  ASSETS: {
    async fetch(request) {
      const path = new URL(request.url).pathname;
      // As the real binding (html_handling auto-trailing-slash): a page's
      // .html address sends to its bare one, a folder's index to the folder.
      if (path.endsWith(".html") && path !== "/index.html") {
        const to = path.endsWith("/index.html") ? path.slice(0, -"index.html".length) : path.slice(0, -".html".length);
        return new Response(null, { status: 301, headers: { Location: to } });
      }
      const [body, type] = files[path] || files[`${path}.html`] || files[`${path}index.html`] || files["/index.html"];
      return new Response(body, { headers: { "Content-Type": type, "Cache-Control": "public, max-age=0, must-revalidate" } });
    },
  },
};

// Cloudflare's HTMLRewriter, played by a small one for the two selectors
// the page uses (title, head): text set is escaped as the real one does.
globalThis.HTMLRewriter = class {
  constructor() { this.handlers = []; }
  on(selector, handler) { this.handlers.push([selector, handler]); return this; }
  transform(response) {
    const handlers = this.handlers;
    const out = response.text().then((html) => {
      for (const [tag, h] of handlers) {
        html = html.replace(new RegExp(`<${tag}(\\s[^>]*)?>([\\s\\S]*?)</${tag}>`, "i"), (m, attrs, inner) => {
          let content = inner, before = "", after = "";
          h.element?.({
            setInnerContent(t) { content = String(t).replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" })[c]); },
            prepend(t) { before += t; },
            append(t) { after += t; },
            getAttribute() { return null; },
            setAttribute() {},
            remove() {},
            onEndTag(cb) { cb({ before(t) { after += t; } }); },
          });
          return `<${tag}${attrs || ""}>${before}${content}${after}</${tag}>`;
        });
      }
      return html;
    });
    const stream = new ReadableStream({
      async start(c) { c.enqueue(new TextEncoder().encode(await out)); c.close(); },
    });
    return new Response(stream, { status: response.status, headers: response.headers });
  }
};

// The project's answer, played by a stub: what it was asked, what it says.
const asked = [];
let answer = null;
globalThis.fetch = async (url) => {
  asked.push(String(url));
  return new Response(JSON.stringify(answer), { headers: { "Content-Type": "application/json" } });
};

const get = (path) => site.fetch(new Request(`https://marakaj.com${path}`), env);

test("a card the server shows: the page under /cartes, the event in it, never cached", async () => {
  answer = {
    slug: "ines-thomas-ab12", kind: "mariage", card: "come", title: "Inès & Thomas <3",
    starts_at: "2027-06-05T15:00:00+00:00", place: "Villa Serena", content: { type: "mariage", "t:names": "Inès &amp; Thomas" },
    rsvp_on: true, album_on: true, published: false, org_name: "Mariages d'Awa", preview: true,
  };
  asked.length = 0;
  const r = await get("/e/ines-thomas-ab12?apercu=f00dbabe");
  assert.equal(r.status, 200);
  assert.equal(r.headers.get("Cache-Control"), "no-store");
  assert.match(r.headers.get("Content-Type"), /text\/html/);
  const html = await r.text();
  assert.ok(html.startsWith("<!doctype html>"), "the card's own page");
  assert.ok(html.includes('<base href="/cartes/">'), "its files resolve under /cartes/");
  assert.ok(html.includes("<title>Inès &amp; Thomas &lt;3 · Marakaj</title>"), "the event's title, escaped");
  assert.ok(html.includes("window.CARTE="), "the event written in");
  assert.ok(html.includes('"title":"Inès & Thomas \\u003c3"'), "angle brackets escaped inside the script");
  assert.ok(html.includes('"preview":"f00dbabe"'), "the preview token kept for the RSVP");
  assert.ok(html.includes('"api":{"url":"https://x.supabase.co","key":"sb_publishable_test"}'), "the public key, for the RSVP");
  assert.ok(html.includes('<meta property="og:title" content="Inès &amp; Thomas &lt;3">'), "og tags escaped");
  assert.ok(html.includes('<meta name="robots" content="noindex">'), "an invitation is not indexed");
  // event_public, then the card's ticket offer (161).
  assert.equal(asked.length, 2);
  assert.equal(new URL(asked[1]).pathname, "/rest/v1/rpc/event_ticket_offer");
  const u = new URL(asked[0]);
  assert.equal(u.pathname, "/rest/v1/rpc/event_public");
  assert.equal(u.searchParams.get("p_slug"), "ines-thomas-ab12");
  assert.equal(u.searchParams.get("p_preview"), "f00dbabe");
});

test("the card the event names; an unknown name falls back to the first", async () => {
  answer = { slug: "gala-x", kind: "gala", card: "gala", title: "Gala", content: {} };
  let html = await (await get("/e/gala-x")).text();
  assert.ok(html.includes("<h1 data-edit=\"names\">Gala</h1>"));
  answer = { slug: "gala-x", kind: "gala", card: "../index", title: "Gala", content: {} };
  html = await (await get("/e/gala-x")).text();
  assert.ok(html.includes("<h1 data-edit=\"names\">Inès</h1>"), "come.html, not a path");
});

test("nothing from the server: not found, not cached; no token means an empty p_preview", async () => {
  answer = null;
  asked.length = 0;
  const r = await get("/e/ines-thomas-ab12");
  assert.equal(r.status, 404);
  assert.equal(r.headers.get("Cache-Control"), "no-store");
  assert.equal(new URL(asked[0]).searchParams.get("p_preview"), "");
});

test("an animated design (153): the page under /evenements, the layout, the day and hour on the organiser's clock", async () => {
  answer = {
    slug: "gala-x", kind: "gala", card: "anime_lotus_p", family: "anime", premium: true, title: "Gala des Anciens",
    starts_at: "2026-12-12T23:00:00+00:00", tz: "-05:00", place: "Hôtel Bravia", content: { pal: 1 }, rsvp_on: true,
  };
  let r = await get("/e/gala-x?apercu=f00dbabe");
  assert.equal(r.status, 200);
  let html = await r.text();
  assert.ok(html.includes("<title>Gala des Anciens · Marakaj</title>"));
  assert.ok(html.includes('<base href="/evenements/">'), "the animated page's folder");
  assert.ok(html.includes('<main id="site">'), "the animated page itself");
  assert.ok(html.includes('"family":"anime"'));
  assert.ok(html.includes('"premium":true'));
  assert.ok(html.includes('"lay":"lotus_p"'), "the layout the page draws");
  assert.ok(html.includes('"date":"2026-12-12"') && html.includes('"time":"18:00"'), "23 h UTC is 18 h at -05:00");
  // A zone's name: the same hour in New York that December day.
  answer = { ...answer, tz: "America/New_York" };
  html = await (await get("/e/gala-x")).text();
  assert.ok(html.includes('"time":"18:00"'), "America/New_York in December is -05:00");
  // Ouagadougou by default, and when the zone is unknown.
  answer = { ...answer, tz: "Mars/Olympus" };
  html = await (await get("/e/gala-x")).text();
  assert.ok(html.includes('"time":"23:00"'));
  answer = { ...answer, tz: null, starts_at: null };
  html = await (await get("/e/gala-x")).text();
  assert.ok(html.includes('"date":null') && html.includes('"time":null'), "no day set: nothing composed");
  // A family said animated with a key that is not one: the first layout.
  answer = { ...answer, card: "../x", family: "anime" };
  html = await (await get("/e/gala-x")).text();
  assert.ok(html.includes('"lay":"lettre"'));
});

test("the organiser's editor (154): « modifier » is asked of the server, and the page told it is the editor", async () => {
  answer = {
    slug: "ines-thomas-ab12", kind: "mariage", card: "come", title: "Inès & Thomas", content: {},
    rsvp_on: true, published: false, preview: false, editor: true,
  };
  asked.length = 0;
  let html = await (await get("/e/ines-thomas-ab12?apercu=f00dbabe&modifier=ed17ed17ed17ed17ed17ed17")).text();
  const u = new URL(asked[0]);
  assert.equal(u.searchParams.get("p_edit"), "ed17ed17ed17ed17ed17ed17", "the edit token asked of event_public");
  assert.equal(u.searchParams.get("p_preview"), "f00dbabe");
  assert.ok(html.includes('"editor":true'), "the page is the editor");
  assert.ok(html.includes('"edit":"ed17ed17ed17ed17ed17ed17"'), "with its token");
  assert.ok(html.includes('"uploads":null'), "no uploads address in this test's env");
  // The server alone says who is the editor: the token in the address is
  // not enough when the server says no.
  answer = { ...answer, editor: false };
  html = await (await get("/e/ines-thomas-ab12?modifier=ed17ed17ed17ed17ed17ed17")).text();
  assert.ok(html.includes('"editor":false') && html.includes('"edit":null'), "not the editor: no token kept");
  // Without « modifier », p_edit is empty and nothing says editor.
  asked.length = 0;
  answer = { ...answer, editor: true };
  html = await (await get("/e/ines-thomas-ab12?apercu=f00dbabe")).text();
  assert.equal(new URL(asked[0]).searchParams.get("p_edit"), "");
  assert.ok(html.includes('"editor":false'));
  // The uploads address, when the env has one.
  html = await (await site.fetch(new Request("https://marakaj.com/e/ines-thomas-ab12?modifier=x"), { ...env, UPLOADS_URL: "https://up.example/" })).text();
  assert.ok(html.includes('"uploads":"https://up.example"'), "the uploads Worker's address, no trailing slash");
});

test("a design's sample (155c): /modele/<key> is the card's page with sample words, demo, cached, nothing asked of the server", async () => {
  asked.length = 0;
  let r = await get("/modele/come");
  assert.equal(r.status, 200);
  assert.equal(r.headers.get("Cache-Control"), "public, max-age=3600");
  let html = await r.text();
  assert.ok(html.includes('<base href="/cartes/">'));
  assert.ok(html.includes('"demo":true'), "the page keeps the answers on the phone");
  assert.ok(html.includes('"title":"Inès & Thomas"') && html.includes('"kind":"mariage"'), "sample words for a wedding card");
  assert.ok(html.includes('"album_on":false') && html.includes('"editor":false'));
  assert.ok(html.includes('<meta property="og:url" content="https://marakaj.com/modele/come">'));
  assert.equal(asked.length, 0, "no event behind it");
  r = await get("/modele/anniv");
  html = await r.text();
  assert.ok(html.includes('"title":"Les 30 ans de Rokia"') && html.includes('"kind":"anniversaire"'), "a birthday card's sample");
  r = await get("/modele/anime_lotus_p");
  html = await r.text();
  assert.ok(html.includes('<base href="/evenements/">') && html.includes('"lay":"lotus_p"') && html.includes('"premium":true'), "an animated design, its layout");
  assert.ok(/"date":"\d{4}-\d\d-\d\d"/.test(html) && html.includes('"time":"15:00"'), "a day ahead, at 15 h in Ouagadougou");
  assert.equal((await get("/modele/nope")).status, 404);
  assert.ok(!(await (await get("/modele/..%2Findex")).text()).includes("window.CARTE="), "not a card: the app's page");
  // Without the project's address the sample still shows: no server behind it.
  const bare = await site.fetch(new Request("https://marakaj.com/modele/come"), { ASSETS: env.ASSETS });
  assert.equal(bare.status, 200);
});

test("the cards' pages are not addresses of their own", async () => {
  const r = await get("/cartes/come.html");
  assert.equal(r.status, 404);
  const css = await get("/cartes/shared.css");
  assert.equal(css.status, 200, "their files are");
  const anime = await get("/evenements/index.html");
  assert.equal(anime.status, 404, "the animated page neither");
  assert.equal((await get("/cartes/come")).status, 404, "nor by its bare address");
  assert.equal((await get("/evenements/")).status, 404, "nor the animated page's folder");
  assert.equal((await get("/cartes/apercu/come.jpg")).status, 200, "its pictures are");
});

test("the real pages take the card's data: each has the <head> the Worker writes into", async () => {
  // The animated page shipped without <html>/<head>/<body> (an artifact
  // fragment): the rewriter's head handler never fired, and every animated
  // card on the live site ran as the bare prototype. The stub above has a
  // head of its own — this test serves the files as they are.
  const { readFileSync } = await import("node:fs");
  const real = {
    "/index.html": files["/index.html"],
    "/cartes/come.html": [readFileSync(new URL("../../../app/web/cartes/come.html", import.meta.url), "utf8"), "text/html; charset=utf-8"],
    "/evenements/index.html": [readFileSync(new URL("../../../app/web/evenements/index.html", import.meta.url), "utf8"), "text/html; charset=utf-8"],
  };
  const realEnv = { ...env, ASSETS: { async fetch(request) {
    const path = new URL(request.url).pathname;
    if (path.endsWith(".html") && path !== "/index.html") {
      const to = path.endsWith("/index.html") ? path.slice(0, -"index.html".length) : path.slice(0, -".html".length);
      return new Response(null, { status: 301, headers: { Location: to } });
    }
    const [body, type] = real[path] || real[`${path}.html`] || real[`${path}index.html`] || real["/index.html"];
    return new Response(body, { headers: { "Content-Type": type } });
  } } };
  for (const [path, base, mark] of [["/modele/anime_lettre", "/evenements/", '"lay":"lettre"'], ["/modele/come", "/cartes/", '"card":"come"']]) {
    const r = await site.fetch(new Request(`https://marakaj.com${path}`), realEnv);
    const html = await r.text();
    assert.equal(r.status, 200, path);
    assert.ok(/<head[\s>]/i.test(html), `${path}: the page has a <head>`);
    assert.ok(html.includes(`<base href="${base}">`), `${path}: its base written in`);
    assert.ok(html.includes("window.CARTE=") && html.includes(mark), `${path}: the card's data written in`);
    assert.ok(html.indexOf("window.CARTE=") < html.indexOf("</head>"), `${path}: before the page's own script`);
  }
});

test("a guest's pass (158): /e/<slug>/invite/<id> reads event_pass, never cached; nothing for a wrong id", async () => {
  const id = "0f0f0f0f-0f0f-4f0f-8f0f-0f0f0f0f0f0f";
  answer = { id, name: "Tanti Rose", people: 2, answer: "oui", arrived_at: null, title: "Inès & Thomas", date_fr: "samedi 5 juin 2027 à 15 h",
    place: "Villa Serena", org_name: "Mariages d'Awa", tz: "Africa/Ouagadougou" };
  asked.length = 0;
  let r = await get(`/e/ines-thomas-ab12/invite/${id}`);
  assert.equal(r.status, 200);
  let html = await r.text();
  assert.ok(html.includes("Tanti Rose") && html.includes("Vient · 2 personnes") && html.includes("Inès &amp; Thomas") && html.includes("Villa Serena") && html.includes("Mariages d'Awa"), html.slice(0, 200));
  assert.ok(!/Arrivé/.test(html), "not arrived yet");
  assert.equal(r.headers.get("Cache-Control"), "no-store");
  const u = new URL(asked[0]);
  assert.equal(u.pathname, "/rest/v1/rpc/event_pass");
  assert.equal(u.searchParams.get("p_slug"), "ines-thomas-ab12");
  assert.equal(u.searchParams.get("p_id"), id);
  answer = { ...answer, people: 1, arrived_at: "2027-06-05T18:05:00+00:00" };
  html = await (await get(`/e/ines-thomas-ab12/invite/${id}`)).text();
  assert.ok(/Arrivé·e à 18:05/.test(html) && html.includes(">Vient<"), "arrived, at Ouagadougou's hour");
  answer = { ...answer, answer: "non" };
  html = await (await get(`/e/ines-thomas-ab12/invite/${id}`)).text();
  assert.ok(html.includes("Ne vient pas"));
  answer = null;
  assert.equal((await get(`/e/ines-thomas-ab12/invite/${id}`)).status, 404, "an unknown pass");
  asked.length = 0;
  assert.equal((await get("/e/ines-thomas-ab12/invite/not-an-id")).status, 404);
  assert.equal(asked.length, 0, "a malformed id never asks the server");
});

test("the ticket pages (161): the offer, the buyer's request, one ticket; never cached; a stranger's id is nothing", async () => {
  const id = "0f0f0f0f-0f0f-4f0f-8f0f-0f0f0f0f0f0f";
  answer = { on: true, open: true, slug: "concert-fatim", title: "Concert Fatim", date_fr: "samedi 12 décembre 2026", place: "CENASA",
    currency: "XOF", hold_hours: 72, org_name: "Awa Concerts", pay_whatsapp: "+22670000001",
    pay_methods: [{ kind: "orange", number: "70 00 00 01", name: "Awa K." }],
    types: [{ id: "t1", name: "Standard", price: 2000, left: 3 }, { id: "t2", name: "VIP", price: 5000, left: 0 }] };
  asked.length = 0;
  let r = await get("/e/concert-fatim/billets");
  let html = await r.text();
  assert.equal(r.status, 200);
  assert.equal(r.headers.get("Cache-Control"), "no-store");
  assert.ok(html.includes("Concert Fatim") && html.includes("Standard") && html.includes("2 000 FCFA") && html.includes("Plus que 3 places"), "the types and their prices");
  assert.ok(html.includes("Complet"), "a sold-out type says so");
  assert.ok(html.includes("gardées 72 heures") && html.includes("Marakaj n’encaisse rien"), "the hold and the notice");
  assert.equal(new URL(asked[0]).pathname, "/rest/v1/rpc/event_ticket_offer");
  answer = { on: false };
  assert.equal((await get("/e/concert-fatim/billets")).status, 404, "no sale, no page");

  answer = { id, ref: "MK-7F3A2", status: "pending", name: "Tanti Rose", total: 9000, currency: "XOF", hold_until: "2026-12-01T10:00:00Z",
    slug: "concert-fatim", title: "Concert Fatim", date_fr: "samedi", place: "CENASA", pay_whatsapp: "+22670000001",
    pay_methods: [{ kind: "orange", number: "70 00 00 01", name: "Awa K." }], lines: [{ name: "Standard", qty: 2, price: 2000 }], tickets: [] };
  html = await (await get(`/e/concert-fatim/billets/${id}`)).text();
  assert.ok(html.includes("MK-7F3A2") && html.includes("Orange Money") && html.includes("70 00 00 01") && html.includes("9 000 FCFA"), "where to pay and the reference");
  assert.ok(html.includes("https://wa.me/22670000001?text="), "the organiser on WhatsApp");
  answer = { ...answer, status: "paid", tickets: [{ id: "a1a1a1a1-a1a1-4a1a-8a1a-a1a1a1a1a1a1", type: "Standard", holder: "Tanti Rose", status: "valid" },
    { id: "b2b2b2b2-b2b2-4b2b-8b2b-b2b2b2b2b2b2", type: "Standard", holder: "Tanti Rose", status: "valid" }] };
  html = await (await get(`/e/concert-fatim/billets/${id}`)).text();
  assert.ok(html.includes("Payé · 2 billets") && html.includes(`data-qr="https://marakaj.com/e/concert-fatim/billet/a1a1a1a1-a1a1-4a1a-8a1a-a1a1a1a1a1a1"`), "one QR per ticket");
  assert.ok(html.includes(`href="/billets/${id}"`), "kept in Marakaj");
  assert.equal((await get(`/e/autre-carte/billets/${id}`)).status, 404, "another card's request: nothing");
  asked.length = 0;
  assert.equal((await get("/e/concert-fatim/billets/nope")).status, 404);
  assert.equal(asked.length, 0, "a malformed id asks nobody");

  answer = { id: "a1a1a1a1-a1a1-4a1a-8a1a-a1a1a1a1a1a1", holder: "Tanti Rose", type: "VIP", status: "used", title: "Concert Fatim", ref: "MK-7F3A2" };
  html = await (await get("/e/concert-fatim/billet/a1a1a1a1-a1a1-4a1a-8a1a-a1a1a1a1a1a1")).text();
  assert.ok(html.includes("Tanti Rose") && html.includes("Déjà utilisé") && html.includes("VIP"), "one ticket");
  answer = null;
});

test("without the project's address, nothing", async () => {
  const r = await site.fetch(new Request("https://marakaj.com/e/x"), { ASSETS: env.ASSETS });
  assert.equal(r.status, 404);
});
