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

test("171d: a classic card without a document goes to Studio too; an animated one keeps its editor until Studio draws its scenes", async () => {
  answers.event_public = card({ editor: true });
  let r = await get(`/e/salimata-boukary-ab12?modifier=${TOKEN}&apercu=f00d`);
  assert.equal(r.status, 302, "« Modifier la carte » opens Studio for every classic card");
  assert.equal(r.headers.get("Location"), `/e/salimata-boukary-ab12/studio?modifier=${TOKEN}&apercu=f00d`);
  // the converter's frame still reads the classic card as it is
  r = await get(`/e/salimata-boukary-ab12?modifier=${TOKEN}&studio=lire`);
  assert.equal(r.status, 200);
  let html = await r.text();
  assert.ok(html.includes('<base href="/cartes/">') && html.includes('"studio":true') && html.includes('"doc":null'));
  // an animated card (its layout, or its family): its own editor, offering Studio
  for (const extra of [{ card: "anime_lettre", family: "anime" }, { card: "anime_lotus_p", family: "classique" }, { card: "come", family: "anime" }]) {
    answers.event_public = card({ editor: true, ...extra });
    r = await get(`/e/salimata-boukary-ab12?modifier=${TOKEN}`);
    assert.equal(r.status, 200, JSON.stringify(extra));
    html = await r.text();
    assert.ok(html.includes('"studio":true') && html.includes('"doc":null'), JSON.stringify(extra));
  }
  // an animated card already made in Studio: Studio, as before
  answers.event_public = card({ editor: true, card: "anime_lettre", family: "anime", doc: DOC });
  r = await get(`/e/salimata-boukary-ab12?modifier=${TOKEN}`);
  assert.equal(r.status, 302);
  // 173 live (event_public says « pro »): every animated card goes to Studio,
  // which draws its living picture; « pro » reaches Studio's boot
  for (const pro of [true, false]) {
    answers.event_public = card({ editor: true, card: "anime_lotus_p", family: "anime", pro });
    r = await get(`/e/salimata-boukary-ab12?modifier=${TOKEN}`);
    assert.equal(r.status, 302, `animated, pro ${pro}`);
    assert.equal(r.headers.get("Location"), `/e/salimata-boukary-ab12/studio?modifier=${TOKEN}`);
    r = await get(`/e/salimata-boukary-ab12/studio?modifier=${TOKEN}`);
    html = await r.text();
    assert.ok(html.includes(`"pro":${pro}`), `Studio told pro ${pro}`);
  }
  // the guests of a classic card without a document: its page, never Studio
  answers.event_public = card({ editor: false });
  r = await get("/e/salimata-boukary-ab12");
  assert.equal(r.status, 200);
  assert.ok((await r.text()).includes('<base href="/cartes/">'));
});

test("171d: the site's own pages choose no word on a long press; the payment number and the reference are copied with a button", async () => {
  // the guest's pass
  answers.event_pass = { name: "Awa", answer: "oui", people: 2, title: "Salimata & Boukary", date_fr: "samedi 17 avril", place: "Tanghin" };
  let r = await get("/e/salimata-boukary-ab12/invite/0b9f3c2e-1d2a-4c5b-9e8f-7a6b5c4d3e2f");
  let html = await r.text();
  assert.ok(html.includes("user-select:none") && html.includes("-webkit-touch-callout:none"), "the pass: " + r.status);
  // a ticket request waiting for its payment
  answers.event_ticket_status = {
    id: "0b9f3c2e-1d2a-4c5b-9e8f-7a6b5c4d3e2f", slug: "salimata-boukary-ab12", status: "pending", title: "Gala", name: "Awa",
    lines: [{ qty: 2, name: "Standard" }], total: 10000, currency: "XOF", ref: "MK-7Q2P", hold_until: "2027-04-10T10:00:00Z",
    pay_methods: [{ kind: "orange", number: "+226 70 00 00 00", name: "Awa" }],
  };
  r = await get("/e/salimata-boukary-ab12/billets/0b9f3c2e-1d2a-4c5b-9e8f-7a6b5c4d3e2f");
  html = await r.text();
  assert.equal(r.status, 200);
  assert.ok(html.includes("user-select:none"), "the ticket page");
  // 178: read with its code, copied without it — as a transfer is typed
  assert.ok(html.includes("+226 70 00 00 00"), "the number read in pairs with its code");
  assert.ok(html.includes('data-cp="70000000">Copier le numéro</button>'), "the number has its button, the local digits");
  assert.ok(html.includes('data-cp="MK-7Q2P">Copier la référence</button>'), "the reference has its button");
  assert.ok(html.includes("navigator.clipboard"), "and the button copies");
  // inputs and the words being written stay choosable
  assert.ok(html.includes('input,textarea,select,[contenteditable]:not([contenteditable="false"]){-webkit-user-select:text;user-select:text'));
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

test("173: a guest's opening is counted once a day, never a robot, the organiser or an unpublished card; a share is counted", async () => {
  const PHONE = "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/130 Mobile Safari/537.36";
  const open = (path, headers = {}) => site.fetch(new Request(`https://marakaj.com${path}`, { headers }), env);
  const counts = () => asked.filter((u) => u.endsWith("/rpc/event_count")).length;
  answers.event_public = card({ doc: DOC });
  asked.length = 0;
  let r = await open("/e/salimata-boukary-ab12", { "User-Agent": PHONE });
  assert.equal(r.status, 200);
  assert.equal(counts(), 1, "a person's first opening: counted");
  const cookie = r.headers.get("Set-Cookie") || "";
  assert.ok(/^mkv_salimata_boukary_ab12=1; Max-Age=\d+; Path=\/e\/salimata-boukary-ab12; Secure; HttpOnly; SameSite=Lax$/.test(cookie), cookie);
  assert.ok((await r.text()).includes('<div id="card" class="st-root">'), "the page itself, untouched");
  await open("/e/salimata-boukary-ab12", { "User-Agent": PHONE, Cookie: "a=b; mkv_salimata_boukary_ab12=1" });
  assert.equal(counts(), 1, "the same day again: not counted");
  for (const ua of ["WhatsApp/2.23.20.0 A", "facebookexternalhit/1.1", "Mozilla/5.0 (compatible; Googlebot/2.1)", ""]) {
    await open("/e/salimata-boukary-ab12", ua ? { "User-Agent": ua } : {});
  }
  assert.equal(counts(), 1, "link previews and crawlers: not counted");
  answers.event_public = card({ doc: DOC, published: false, preview: true });
  await open("/e/salimata-boukary-ab12?apercu=f00d", { "User-Agent": PHONE });
  assert.equal(counts(), 1, "a card not yet published: not counted");
  answers.event_public = card({ doc: DOC, editor: true });
  await open(`/e/salimata-boukary-ab12?modifier=${TOKEN}`, { "User-Agent": PHONE });
  assert.equal(counts(), 1, "the organiser: not counted");
  r = await site.fetch(new Request("https://marakaj.com/e/salimata-boukary-ab12/partage", { method: "POST", headers: { "User-Agent": PHONE } }), env);
  assert.equal(r.status, 204);
  assert.equal(counts(), 2, "a share: counted");
});

test("173: a shared card's link shows its own photo (og:image)", async () => {
  const KEY = "events/0b9f3c2e-1d2a-4c5b-9e8f-7a6b5c4d3e2f/0123456789abcdef0123456789abcdef.jpg";
  const env2 = { ...env, UPLOADS_URL: "https://up.marakaj.com/" };
  const og = async (answer) => {
    answers.event_public = answer;
    const html = await (await site.fetch(new Request("https://marakaj.com/e/salimata-boukary-ab12"), env2)).text();
    const m = /<meta property="og:image" content="([^"]*)">/.exec(html);
    return m ? m[1] : null;
  };
  const withCover = { ...DOC, blocks: [{ id: "b0", type: "text", props: { photo: { stock: "wed-lake" } } }, { id: "b1", type: "cover", props: { photo: { key: KEY, pos: [50, 40] } } }] };
  assert.equal(await og(card({ doc: withCover })), `https://up.marakaj.com/v1/public/objects/${encodeURIComponent(KEY)}?w=1200`, "the cover's photo first");
  assert.equal(await og(card({ doc: { ...DOC, blocks: [{ id: "b1", type: "gallery", props: { photos: [{ stock: "wed-lake" }] } }] } })), "https://marakaj.com/cartes/img/wed-lake.jpg", "a bank photo");
  assert.equal(await og(card({ doc: null, content: { "p:p1": { key: KEY } } })), `https://up.marakaj.com/v1/public/objects/${encodeURIComponent(KEY)}?w=1200`, "a classic card's photo");
  assert.equal(await og(card({ doc: DOC })), null, "no photo: no og:image");
  assert.equal(await og(card({ doc: { ...DOC, blocks: [{ id: "b1", type: "photo", props: { photo: { key: "../../etc" } } }] } })), null, "a key that is not one: nothing");
});

test("173c: the iPhone app's links — Apple's file, JSON, the buying and ticket paths only", async () => {
  for (const path of ["/.well-known/apple-app-site-association", "/apple-app-site-association"]) {
    const r = await get(path);
    assert.equal(r.status, 200, path);
    assert.equal(r.headers.get("Content-Type"), "application/json");
    const j = await r.json();
    const d = j.applinks.details[0];
    assert.deepEqual(d.appIDs, ["9K236BL7SX.bf.kaj.app"]);
    const paths = d.components.map((c) => c["/"]);
    assert.deepEqual(paths, ["/achat-billets/*", "/billets", "/billets/*"]);
    assert.ok(!paths.some((p) => p.startsWith("/e/")), "the cards stay web pages");
  }
});

test("173c: the Android app's links — the Play signing key, the package, JSON", async () => {
  const r = await get("/.well-known/assetlinks.json");
  assert.equal(r.status, 200);
  assert.equal(r.headers.get("Content-Type"), "application/json");
  const [j] = await r.json();
  assert.deepEqual(j.relation, ["delegate_permission/common.handle_all_urls"]);
  assert.equal(j.target.package_name, "bf.kaj.app");
  assert.deepEqual(j.target.sha256_cert_fingerprints, ["5C:29:33:1F:CE:64:5C:D0:BA:3F:B7:EA:72:30:6C:A4:63:1B:FE:93:FD:43:22:32:39:8F:46:3D:04:77:D1:AA"]);
});

test("178: a payment number stored with its country is read in pairs and copied without its code", async () => {
  const { phoneText, phoneLocal } = await import("../src/index.js");
  assert.equal(phoneText("+22670000001"), "+226 70 00 00 01");
  assert.equal(phoneLocal("+22670000001"), "70000001");
  assert.equal(phoneText("+2250712345678"), "+225 07 12 34 56 78", "Côte d'Ivoire keeps its zero");
  assert.equal(phoneLocal("+2250712345678"), "0712345678");
  assert.equal(phoneText("70 00 00 01"), "70 00 00 01", "a number typed before, as it was");
});
