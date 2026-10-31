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
const files = {
  "/index.html": [PAGE, "text/html; charset=utf-8"],
  "/cartes/come.html": [CARD, "text/html; charset=utf-8"],
  "/cartes/gala.html": [CARD.replaceAll("Inès", "Gala"), "text/html; charset=utf-8"],
  "/cartes/shared.css": ["body{}", "text/css"],
};
const env = {
  SUPABASE_URL: "https://x.supabase.co",
  SUPABASE_PUBLISHABLE_KEY: "sb_publishable_test",
  ASSETS: {
    async fetch(request) {
      const path = new URL(request.url).pathname;
      const [body, type] = files[path] || files["/index.html"];
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
  assert.equal(asked.length, 1);
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

test("the cards' pages are not addresses of their own", async () => {
  const r = await get("/cartes/come.html");
  assert.equal(r.status, 404);
  const css = await get("/cartes/shared.css");
  assert.equal(css.status, 200, "their files are");
});

test("without the project's address, nothing", async () => {
  const r = await site.fetch(new Request("https://marakaj.com/e/x"), { ASSETS: env.ASSETS });
  assert.equal(r.status, 404);
});
