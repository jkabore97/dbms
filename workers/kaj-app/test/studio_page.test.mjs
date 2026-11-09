// Studio (171): /e/<slug>/studio is the organiser's editor, /e/<slug> the
// guests' page of a card made in Studio; an organiser whose card has a
// document is sent to Studio; nothing breaks before the migration is live.
//
//   node --test workers/kaj-app/test/*.test.mjs

import assert from "node:assert/strict";
import { test } from "node:test";

import site from "../src/index.js";

const PAGE = "<!DOCTYPE html><html><head><title>Marakaj</title></head><body></body></html>";
const CARD = '<!doctype html><html lang="fr"><head><meta charset="utf-8"><title>Inès & Thomas</title>'
  + '</head><body><article class="card"><h1 data-edit="names">Inès</h1></article><script src="shared.js"></script></body></html>';
const EDITOR = '<!doctype html><html lang="fr"><head><meta charset="utf-8"><title>Studio · Marakaj</title>'
  + '<link rel="stylesheet" href="studio.css"></head><body class="ed-body"><div id="app"></div><script src="editor.js"></script></body></html>';
const GUESTS = '<!doctype html><html lang="fr"><head><meta charset="utf-8"><title>Invitation · Marakaj</title>'
  + '</head><body><div id="card" class="st-root"></div><script src="card.js"></script></body></html>';
const files = {
  "/index.html": [PAGE, "text/html; charset=utf-8"],
  "/cartes/come.html": [CARD, "text/html; charset=utf-8"],
  "/cartes/studio/editor.html": [EDITOR, "text/html; charset=utf-8"],
  "/cartes/studio/card.html": [GUESTS, "text/html; charset=utf-8"],
  "/cartes/studio/render.js": ["window.Studio={};", "text/javascript"],
};
const env = {
  SUPABASE_URL: "https://x.supabase.co",
  SUPABASE_PUBLISHABLE_KEY: "sb_publishable_test",
  ASSETS: {
    async fetch(request) {
      const path = new URL(request.url).pathname;
      // As the real binding (html_handling auto-trailing-slash).
      if (path.endsWith(".html") && path !== "/index.html") {
        return new Response(null, { status: 301, headers: { Location: path.slice(0, -".html".length) } });
      }
      const [body, type] = files[path] || files[`${path}.html`] || files["/index.html"];
      return new Response(body, { headers: { "Content-Type": type } });
    },
  },
};

// Cloudflare's HTMLRewriter, played by a small one (title, head).
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
          });
          return `<${tag}${attrs || ""}>${before}${content}${after}</${tag}>`;
        });
      }
      return html;
    });
    const stream = new ReadableStream({ async start(c) { c.enqueue(new TextEncoder().encode(await out)); c.close(); } });
    return new Response(stream, { status: response.status, headers: response.headers });
  }
};

// The project, played by a stub: each function its own answer.
const asked = [];
const answers = {};
globalThis.fetch = async (url) => {
  asked.push(String(url));
  const fn = new URL(String(url)).pathname.split("/").pop();
  return new Response(JSON.stringify(answers[fn] ?? null), { headers: { "Content-Type": "application/json" } });
};
const get = (path) => site.fetch(new Request(`https://marakaj.com${path}`), env);
const TOKEN = "ed17ed17ed17ed17ed17ed17";
const DOC = {
  v: 2,
  theme: { preset: "dot", colors: { back: "#0f6b4f", paper: "#fbf5e8", ink: "#1f2a23", accent: "#c2185b" } },
  blocks: [{ id: "b1", type: "cover", variant: "cadre", props: { names: "Salimata & Boukary", kicker: "</script><script>alert(1)</script>" } }],
};
const card = (extra) => ({
  slug: "salimata-boukary-ab12", kind: "dot", card: "come", family: "classique", title: "Salimata & Boukary",
  starts_at: "2027-04-17T10:00:00+00:00", tz: "Africa/Ouagadougou", place: "Tanghin", content: {},
  rsvp_on: true, album_on: true, published: true, org_name: "Awa Événements", preview: false, editor: false,
  doc: null, doc_saved_at: null, ...extra,
});

test("Studio for the organiser: the editor page, the card written in, the token kept, never cached", async () => {
  answers.event_public = card({ editor: true });
  answers.event_ticket_offer = { on: false };
  asked.length = 0;
  const r = await get(`/e/salimata-boukary-ab12/studio?modifier=${TOKEN}&apercu=f00d`);
  assert.equal(r.status, 200);
  assert.equal(r.headers.get("Cache-Control"), "no-store");
  const html = await r.text();
  assert.ok(html.includes('<base href="/cartes/studio/">'), "its files under /cartes/studio/");
  assert.ok(html.includes('<div id="app">'), "the editor's own page");
  assert.ok(html.includes("<title>Studio · Salimata &amp; Boukary</title>"));
  assert.ok(html.includes(`"edit":"${TOKEN}"`) && html.includes('"editor":true'), "the token it saves with");
  assert.ok(html.includes('"doc":null'), "no document yet: the editor converts the card");
  assert.ok(html.includes('"date":"2027-04-17"') && html.includes('"time":"10:00"'), "the day on the organiser's clock");
  assert.ok(html.includes('"preview":"f00d"'));
  const u = new URL(asked[0]);
  assert.equal(u.pathname, "/rest/v1/rpc/event_public");
  assert.equal(u.searchParams.get("p_edit"), TOKEN, "the server asked whether this is the editor");
});

test("Studio with a document: the document in the boot, its texts unable to close the script", async () => {
  answers.event_public = card({ editor: true, doc: DOC, doc_saved_at: "2026-11-09T17:00:00Z" });
  const html = await (await get(`/e/salimata-boukary-ab12/studio?modifier=${TOKEN}`)).text();
  assert.ok(html.includes('"doc":{"v":2'), "the document");
  assert.ok(html.includes('"doc_saved_at":"2026-11-09T17:00:00Z"'));
  assert.ok(!html.includes("</script><script>alert"), "no « </script> » from a text");
  assert.ok(html.includes("\\u003c/script>"), "written as \\u003c");
});

test("Studio refused: no token, a token the server does not take, no project", async () => {
  asked.length = 0;
  let r = await get("/e/salimata-boukary-ab12/studio");
  assert.equal(r.status, 404);
  assert.equal(asked.length, 0, "nothing asked without a token");
  answers.event_public = card({ editor: false });
  r = await get(`/e/salimata-boukary-ab12/studio?modifier=${TOKEN}`);
  assert.equal(r.status, 404);
  const html = await r.text();
  assert.ok(!html.includes(TOKEN) && !html.includes('id="app"'), "neither the token nor the editor");
  answers.event_public = null;
  r = await get(`/e/salimata-boukary-ab12/studio?modifier=${TOKEN}`);
  assert.equal(r.status, 404);
  r = await site.fetch(new Request(`https://marakaj.com/e/x/studio?modifier=${TOKEN}`), { ...env, SUPABASE_URL: "" });
  assert.equal(r.status, 404);
});

test("before migration 171 is live (no « doc » in the answer): a page that leads back to the card's editor", async () => {
  const old = card({ editor: true });
  delete old.doc; delete old.doc_saved_at;
  answers.event_public = old;
  const r = await get(`/e/salimata-boukary-ab12/studio?modifier=${TOKEN}`);
  assert.equal(r.status, 200);
  const html = await r.text();
  assert.ok(html.includes("Studio arrive bientôt"));
  assert.ok(html.includes(`href="/e/salimata-boukary-ab12?modifier=${TOKEN}"`), "back to the editor they know");
  assert.ok(!html.includes('id="app"'), "not the editor");
  // and the classic editor offers no Studio
  answers.event_ticket_offer = { on: false };
  const ed = await (await get(`/e/salimata-boukary-ab12?modifier=${TOKEN}`)).text();
  assert.ok(ed.includes('"studio":false'), "the old editors hide the Studio entry");
});

test("the guests of a card made in Studio: Studio's page draws the document", async () => {
  answers.event_public = card({ doc: DOC });
  const r = await get("/e/salimata-boukary-ab12");
  assert.equal(r.status, 200);
  assert.equal(r.headers.get("Cache-Control"), "no-store");
  const html = await r.text();
  assert.ok(html.includes('<base href="/cartes/studio/">'));
  assert.ok(html.includes('<div id="card" class="st-root">'), "Studio's guests' page");
  assert.ok(html.includes('"doc":{"v":2'), "the document written in");
  assert.ok(html.includes('"editor":false') && html.includes('"edit":null'), "no editing for the guests");
  assert.ok(html.includes('<meta property="og:title" content="Salimata &amp; Boukary">'), "shared links as before");
});

test("the organiser of a card made in Studio is sent to Studio; « studio=lire » reads the card it was made from", async () => {
  answers.event_public = card({ editor: true, doc: DOC });
  let r = await get(`/e/salimata-boukary-ab12?modifier=${TOKEN}&apercu=f00d`);
  assert.equal(r.status, 302);
  assert.equal(r.headers.get("Location"), `/e/salimata-boukary-ab12/studio?modifier=${TOKEN}&apercu=f00d`);
  assert.equal(r.headers.get("Cache-Control"), "no-store");
  r = await get(`/e/salimata-boukary-ab12?modifier=${TOKEN}&studio=lire`);
  assert.equal(r.status, 200);
  const html = await r.text();
  assert.ok(html.includes('<base href="/cartes/">') && html.includes('data-edit="names"'), "the model's page");
  assert.ok(html.includes('"doc":null') && html.includes('"studio":true'));
  // A token the server does not take: the guests' page, no redirect.
  answers.event_public = card({ editor: false, doc: DOC });
  r = await get(`/e/salimata-boukary-ab12?modifier=${TOKEN}`);
  assert.equal(r.status, 200);
  assert.ok((await r.text()).includes('<div id="card" class="st-root">'));
});

test("a card without a document, once the server keeps documents: the classic editor, offering Studio", async () => {
  answers.event_public = card({ editor: true });
  const html = await (await get(`/e/salimata-boukary-ab12?modifier=${TOKEN}`)).text();
  assert.ok(html.includes('<base href="/cartes/">'));
  assert.ok(html.includes('"studio":true') && html.includes('"doc":null'));
});

test("Studio's pages are not addresses of their own; its scripts are", async () => {
  for (const p of ["/cartes/studio/editor.html", "/cartes/studio/editor", "/cartes/studio/card.html", "/cartes/studio/card", "/cartes/studio/"]) {
    const r = await get(p);
    assert.equal(r.status, 404, p);
  }
  const js = await get("/cartes/studio/render.js");
  assert.equal(js.status, 200);
  assert.equal(await js.text(), "window.Studio={};");
});
