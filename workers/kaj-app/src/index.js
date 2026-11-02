// The site in front of the Flutter web build (assets in ../../app/build/web).
//
// Three jobs, then the static files as before:
//
//  1. One address. Every request that reaches the old
//     dbms.kabore-boss.workers.dev name is sent, for good, to the same path
//     on marakaj.com — a link shared from the old name keeps working and
//     every new share carries the real one.
//
//  2. A vitrine shared on WhatsApp shows the shop, not Mara. WhatsApp,
//     Facebook and the rest read the page's <meta property="og:…"> tags and
//     never run the app, so /s/<slug> gets the shop's own name, its line and
//     its photo written into index.html before it leaves: « Tony Pizza — La
//     pizza du quartier », with the pizza. Anything that goes wrong (no such
//     shop, Supabase down) serves the page untouched, with Mara's tags.
//
//  3. /confidentialite and /conditions are plain pages (legal.js), readable
//     with no JavaScript — what Google's verification of the sign-in screen
//     reads. ?lang=en gives their English translation (147); the terms name
//     the support e-mail support_contacts says.
//
//  3b. /aide is « Aide Mara » (help.js), the App Store's Support URL: the
//     support e-mail, WhatsApp number and hours read live (126's
//     support_contacts), the defaults when Supabase does not answer.
//     /support and /aide/ are sent there for good.
//
//  3c. /sb/rest/v1/… is PostgREST, passed on to the project as it is
//     (supabase_proxy.js): the web app's reads from its own origin, with no
//     preflight before each one. Nothing else under /sb/.
//
//  4. How long a phone may keep each file (cacheFor, below). Set here, not
//     only in _headers: with run_worker_first, Cloudflare applies _headers
//     to nothing this Worker returns. The deploy moves every file that
//     changes between builds into a folder named after its content
//     (scripts/web-fingerprint.mjs): those are kept a year and never asked
//     about again. The page itself, the service workers and version.json
//     say which build is current, so they are asked about every time.
//
// SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY and UPLOADS_URL come from the deploy
// (deploy-cloudflare.yml, from the repository's secrets and variables),
// never from this file. The publishable key is the one the web app already
// ships to every browser.

import { mapsLink } from "./maps.js";
import { isLegalPath, legalPage } from "./legal.js";
import { helpPage, supportContacts } from "./help.js";
import { isProxyPath, proxySupabase } from "./supabase_proxy.js";

const SITE = "https://marakaj.com";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    // The project's answer goes back exactly as it came: none of the
    // site's own headers are added to it.
    if (isProxyPath(url.pathname) && !url.hostname.endsWith(".workers.dev")) {
      return proxySupabase(request, env);
    }
    return secure(await serve(request, env));
  },
};

// The headers web filters (company VPNs such as Zscaler, browsers' own
// checks) look for on a trustworthy site: HTTPS only from now on, no type
// guessing, no framing by another site, the referrer kept to the origin,
// and the phone features the app uses (camera, position) for this site
// only. No Content-Security-Policy: the Flutter engine compiles
// WebAssembly and a wrong policy is a blank page.
const SECURITY_HEADERS = {
  "Strict-Transport-Security": "max-age=31536000",
  "X-Content-Type-Options": "nosniff",
  "X-Frame-Options": "SAMEORIGIN",
  "Referrer-Policy": "strict-origin-when-cross-origin",
  "Permissions-Policy": "camera=(self), geolocation=(self), microphone=(), payment=(self)",
  // Everything this Worker serves is public (the app's files, the
  // vitrines' previews, the legal pages): any origin may read it. That is
  // what lets the app start behind a company proxy such as Zscaler, which
  // sends each file through its own address and back (« ?_sm_nck=1 »): the
  // browser then counts the answer as cross-origin, and without this
  // header refuses the engine (canvaskit.wasm) and the manifest.
  "Access-Control-Allow-Origin": "*",
};

export function secure(response) {
  if (response.status >= 300 && response.status < 400) return response;
  const out = new Response(response.body, response);
  for (const [name, value] of Object.entries(SECURITY_HEADERS)) {
    if (!out.headers.has(name)) out.headers.set(name, value);
  }
  return out;
}

async function serve(request, env) {
  {
    const url = new URL(request.url);

    if (url.hostname.endsWith(".workers.dev")) {
      return Response.redirect(`${SITE}${url.pathname}${url.search}`, 301);
    }

    // The privacy policy and the terms, as plain pages (legal.js).
    // The terms name the platform's support e-mail (147): read as /aide
    // reads it, the installed one when Supabase does not answer.
    if (request.method === "GET" && isLegalPath(url.pathname)) {
      const email = url.pathname.startsWith("/conditions")
        ? (await supportContacts(env)).email
        : undefined;
      const legal = legalPage(url.pathname, { email, lang: url.searchParams.get("lang") });
      if (legal) return legal;
    }

    // « Aide Mara » (help.js), and the addresses that lead to it.
    if (request.method === "GET" || request.method === "HEAD") {
      if (url.pathname === "/support" || url.pathname === "/support/" || url.pathname === "/aide/") {
        return Response.redirect(`${url.origin}/aide${url.search}`, 301);
      }
      if (url.pathname === "/aide") return helpPage(await supportContacts(env));
    }

    // A short Google Maps link's position (maps.js).
    if (url.pathname === "/api/maps-link" && request.method === "GET") {
      return mapsLink(request);
    }

    // An event's card (152): the card's page under /cartes with the
    // event's words written into it. The preview link's token (« apercu »)
    // opens it before it is published, and before the platform opens the
    // module to everyone; the server (event_public) decides either way.
    const event = url.pathname.match(/^\/e\/([a-z0-9-]+)\/?$/);
    if (event && request.method === "GET") {
      return eventPage(request, env, event[1], url.searchParams.get("apercu"), url.searchParams.get("modifier"));
    }
    // /e/<slug>/invite/<id> — a guest's pass (158): what the QR on their
    // answer opens. The id is the key; the server (event_pass) decides.
    // /e/<slug>/billets — a ticket request (161); /e/<slug>/billets/<id> —
    // the buyer's request, where to pay, then the tickets; /e/<slug>/billet/
    // <id> — one ticket, as its QR opens it.
    const tickets = url.pathname.match(/^\/e\/([a-z0-9-]+)\/billets\/?$/);
    if (tickets && request.method === "GET") {
      return ticketsPage(env, tickets[1], url.searchParams.get("apercu"));
    }
    const mine = url.pathname.match(/^\/e\/([a-z0-9-]+)\/billets\/([^/]+)\/?$/);
    if (mine && request.method === "GET") {
      return ticketStatusPage(env, mine[1], mine[2]);
    }
    const one = url.pathname.match(/^\/e\/([a-z0-9-]+)\/billet\/([^/]+)\/?$/);
    if (one && request.method === "GET") {
      return ticketPage(env, one[1], one[2]);
    }
    const pass = url.pathname.match(/^\/e\/([a-z0-9-]+)\/invite\/([^/]*)\/?$/);
    if (pass && request.method === "GET") {
      return passPage(env, pass[1], pass[2]);
    }
    // /modele/<key> — a design shown as a card, with sample words (155c):
    // what the app's gallery opens on « Voir le modèle en vrai ».
    const demo = url.pathname.match(/^\/modele\/([a-z0-9_]+)\/?$/);
    if (demo && request.method === "GET") {
      return demoPage(request, env, demo[1]);
    }
    // The cards' pages — the twelve under /cartes, the animated one under
    // /evenements — are not addresses of their own: only /e/<slug> is.
    if (/^\/(cartes\/[a-z]+(\.html)?|evenements\/(index\.html)?)$/.test(url.pathname)) {
      return new Response("Introuvable.", {
        status: 404,
        headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" },
      });
    }

    const shop = url.pathname.match(/^\/s\/([a-z0-9-]+)\/?$/);
    if (shop && request.method === "GET") {
      try {
        return cacheFor(url.pathname, await vitrinePage(request, env, shop[1]));
      } catch (_) {
        // Mara's own preview rather than no page.
      }
    }
    return cacheFor(url.pathname, await env.ASSETS.fetch(request));
  }
}

// /app/<hash>/, /ck/<hash>/, /a/<hash>/ — written by the deploy.
const FINGERPRINTED = /^\/(app|ck|a)\/[0-9a-f]{12}\//;
// The files that say which build is current.
const ALWAYS_ASK = new Set([
  "/mara_sw.js",
  "/push_sw.js",
  "/push_handlers.js",
  "/flutter_service_worker.js",
  "/version.json",
]);

function cacheFor(path, response) {
  const type = response.headers.get("Content-Type") || "";
  if (FINGERPRINTED.test(path)) {
    // A folder of a build that is no longer deployed: the assets binding
    // would answer the app's page (single-page-application), and a tab of
    // the previous build would run HTML as its business half. Say « not
    // found » instead; the tab's update banner already offers the new one.
    if (type.startsWith("text/html")) {
      return new Response("Introuvable.", {
        status: 404,
        headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" },
      });
    }
    if (response.status === 200 || response.status === 304) {
      return withCacheControl(response, "public, max-age=31536000, immutable");
    }
    return response;
  }
  if (ALWAYS_ASK.has(path) || type.startsWith("text/html")) {
    return withCacheControl(response, "no-cache");
  }
  return response;
}

function withCacheControl(response, value) {
  const out = new Response(response.body, response);
  out.headers.set("Cache-Control", value);
  return out;
}

async function vitrinePage(request, env, slug) {
  const page = await env.ASSETS.fetch(new Request(new URL("/", request.url), request));
  if (!env.SUPABASE_URL || !env.SUPABASE_PUBLISHABLE_KEY) return page;

  const [rows, items] = await Promise.all([
    rpc(env, "storefront", { p_slug: slug }),
    rpc(env, "storefront_products", { p_slug: slug }),
  ]);
  const s = Array.isArray(rows) ? rows[0] : null;
  if (!s || !s.name) return page;

  const style = s.style || {};
  const line = clip(style.tagline || s.blurb || "", 120);
  const count = Array.isArray(items) ? items.length : 0;
  const title = line ? `${s.name} — ${line}` : `${s.name} — sur Marakaj`;
  const description = [
    s.blurb && s.blurb !== line ? clip(s.blurb, 160) : null,
    count > 0 ? `${count} article${count > 1 ? "s" : ""} en vitrine` : null,
    "Commandez sur Marakaj.",
  ].filter(Boolean).join(" · ");

  // The cover the shop chose, else its first photographed article.
  const photo = style.cover_key
    || (Array.isArray(items) ? (items.find((i) => i.photo_key) || {}).photo_key : null);
  const image = photoUrl(env, photo);
  const pageUrl = `${SITE}/s/${slug}`;

  const meta = {
    "og:title": title,
    "og:description": description,
    "og:url": pageUrl,
    "og:type": "website",
    "twitter:title": title,
    "twitter:description": description,
  };
  if (image) {
    meta["og:image"] = image;
    meta["twitter:image"] = image;
  }

  const seen = new Set();
  const rewritten = new HTMLRewriter()
    .on("title", { element(e) { e.setInnerContent(`${s.name} · Marakaj`); } })
    .on('meta[name="description"]', {
      element(e) { e.setAttribute("content", description); },
    })
    .on("meta[property], meta[name]", {
      element(e) {
        const key = e.getAttribute("property") || e.getAttribute("name");
        if (key in meta) {
          e.setAttribute("content", meta[key]);
          seen.add(key);
        }
        // The kit's 1024×500 sizes would be wrong for a shop's own photo.
        if (image && (key === "og:image:width" || key === "og:image:height")) e.remove();
      },
    })
    // The tags index.html does not carry (og:url, the twitter title…).
    .on("head", {
      element(e) {
        e.onEndTag((end) => {
          const missing = Object.keys(meta).filter((k) => !seen.has(k));
          end.before(missing.map((k) => {
            const attr = k.startsWith("og:") ? "property" : "name";
            return `<meta ${attr}="${k}" content="${escapeHtml(meta[k])}">`;
          }).join(""), { html: true });
        });
      },
    })
    .transform(page);

  const headers = new Headers(rewritten.headers);
  // Asked about every time, like every page of the app: it names the
  // build's folders, and a copy kept past a deploy would point at folders
  // that are gone. A shop's new name or photo shows at once, too.
  headers.set("Cache-Control", "no-cache");
  return new Response(rewritten.body, { status: 200, headers });
}

function photoUrl(env, key) {
  if (!key) return null;
  if (key.startsWith("showcase/")) return `${SITE}/${key}`;
  if (!env.UPLOADS_URL) return null;
  return `${env.UPLOADS_URL.replace(/\/$/, "")}/v1/public/objects/${encodeURIComponent(key)}`;
}

// Asked with GET (both functions are STABLE, which PostgREST lets a GET
// call): Cloudflare keeps a GET's answer for cacheTtl, never a POST's. As a
// POST every vitrine page waited on two fresh calls to Supabase before its
// first byte left; now a shop opened in the last five minutes is answered
// from the edge. The data is the public vitrine, the same for everyone.
export function rpcUrl(env, fn, params) {
  const url = new URL(`${String(env.SUPABASE_URL).replace(/\/+$/, "")}/rest/v1/rpc/${fn}`);
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);
  return url.toString();
}

async function rpc(env, fn, params) {
  const response = await fetch(rpcUrl(env, fn, params), {
    method: "GET",
    headers: {
      apikey: env.SUPABASE_PUBLISHABLE_KEY,
      Authorization: `Bearer ${env.SUPABASE_PUBLISHABLE_KEY}`,
    },
    cf: { cacheTtl: 300, cacheEverything: true },
  });
  if (!response.ok) return null;
  return response.json();
}

// The twelve cards (app/web/cartes): the event names one, else the first.
const EVENT_CARDS = new Set([
  "come", "ravello", "sahel", "jardin", "minuit", "anniv",
  "bapteme", "naissance", "diplome", "gala", "dot", "hommage",
  "cimbrone", "bouquet", "rivage",
]);
// An animated design's key (event_templates, 153): anime_<layout>, the
// Premium ones anime_<layout>_p.
const ANIMATED = /^anime_[a-z]+(_p)?$/;

// The day and hour of an instant on the organiser's clock: the zone's name
// (Africa/Ouagadougou, America/New_York) or the phone's offset for that
// day (« -05:00 »); an unknown zone reads on Ouagadougou's clock.
function localParts(iso, tz) {
  const none = { date: null, time: null };
  if (!iso) return none;
  const t = new Date(iso);
  if (Number.isNaN(t.getTime())) return none;
  const pad = (n) => String(n).padStart(2, "0");
  const offset = /^([+-])(\d\d):(\d\d)$/.exec(String(tz || ""));
  if (offset) {
    const minutes = (offset[1] === "-" ? -1 : 1) * (Number(offset[2]) * 60 + Number(offset[3]));
    const l = new Date(t.getTime() + minutes * 60000);
    return {
      date: `${l.getUTCFullYear()}-${pad(l.getUTCMonth() + 1)}-${pad(l.getUTCDate())}`,
      time: `${pad(l.getUTCHours())}:${pad(l.getUTCMinutes())}`,
    };
  }
  for (const zone of [tz, "Africa/Ouagadougou"]) {
    if (!zone) continue;
    try {
      const parts = new Intl.DateTimeFormat("en-CA", {
        timeZone: zone, year: "numeric", month: "2-digit", day: "2-digit",
        hour: "2-digit", minute: "2-digit", hourCycle: "h23",
      }).formatToParts(t);
      const p = Object.fromEntries(parts.filter((x) => x.type !== "literal").map((x) => [x.type, x.value]));
      return { date: `${p.year}-${p.month}-${p.day}`, time: `${p.hour}:${p.minute}` };
    } catch (_) {
      // An unknown zone: the next.
    }
  }
  return none;
}

// /e/<slug> — the card page with the event in it (152). Never cached:
// a preview link is private, and the organiser's change shows at once.
// With « modifier » (the edit token, 154) the page is the organiser's
// editor: the server says « editor », the page shows its bar, saves to
// the server and uploads its pictures through the uploads Worker.
export async function eventPage(request, env, slug, preview, edit) {
  const gone = () => new Response("Cette carte n'est pas ouverte.", {
    status: 404,
    headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" },
  });
  if (!env.SUPABASE_URL || !env.SUPABASE_PUBLISHABLE_KEY) return gone();
  let data = null;
  try {
    data = await rpcFresh(env, "event_public", { p_slug: slug, p_preview: preview || "", p_edit: edit || "" });
  } catch (_) {
    data = null;
  }
  if (!data || typeof data !== "object" || !data.title) return gone();
  // A card that sells tickets (161) shows « Réserver mes billets » instead
  // of its answer form.
  try {
    const offer = await rpcFresh(env, "event_ticket_offer", { p_slug: slug, p_preview: preview || "" });
    data.tickets = !!(offer && offer.on === true);
  } catch (_) {
    data.tickets = false;
  }
  const editor = data.editor === true && !!edit;
  return cardPage(request, env, { slug, data, preview, edit: editor ? edit : null, editor, demo: false });
}

// /e/<slug>/invite/<id> — a guest's pass (158): their name, how many they
// come with, the event, the day, the place, and whether they have
// arrived — read by event_pass with the answer's id as the key. Shown to
// whoever holds the QR: the guest at the door, the organiser who scans
// it. Never cached.
export async function passPage(env, slug, id) {
  const gone = (text) => new Response(text, {
    status: 404,
    headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" },
  });
  // The id is an answer's uuid; anything else is no pass, asked of nobody.
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(id)) return gone("Cette carte d'invité n'existe pas.");
  if (!env.SUPABASE_URL || !env.SUPABASE_PUBLISHABLE_KEY) return gone("Cette carte d'invité n'est pas disponible.");
  let p = null;
  try {
    p = await rpcFresh(env, "event_pass", { p_slug: slug, p_id: id });
  } catch (_) {
    p = null;
  }
  if (!p || typeof p !== "object" || !p.name) return gone("Cette carte d'invité n'existe pas.");
  const tz = typeof p.tz === "string" && p.tz.includes("/") ? p.tz : "Africa/Ouagadougou";
  let arrived = "";
  if (p.arrived_at) {
    try {
      arrived = `Arrivé·e à ${new Date(p.arrived_at).toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit", timeZone: tz })}`;
    } catch (_) {
      arrived = "Arrivé·e";
    }
  }
  const people = Number(p.people) || 1;
  const status = p.answer === "non" ? "Ne vient pas" : p.answer === "mot" ? "A laissé un mot" : people > 1 ? `Vient · ${people} personnes` : "Vient";
  const line = (s) => (s ? `<p>${escapeHtml(String(s))}</p>` : "");
  const html = `<!doctype html><html lang="fr"><head><meta charset="utf-8">` +
    `<meta name="viewport" content="width=device-width, initial-scale=1"><meta name="robots" content="noindex">` +
    `<title>Carte d'invité · ${escapeHtml(String(p.title || ""))}</title>` +
    `<style>body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:#f4efe6;color:#1a140c;font-family:Georgia,"Times New Roman",serif}` +
    `main{max-width:420px;margin:24px;padding:28px 24px;background:#fff;border-radius:20px;box-shadow:0 20px 60px -30px rgba(0,0,0,.4);text-align:center}` +
    `.eye{font:600 11px system-ui,sans-serif;letter-spacing:.2em;text-transform:uppercase;color:#8a6d3b}h1{font-size:30px;margin:10px 0 4px;font-weight:500}` +
    `.st{display:inline-block;margin:8px 0 18px;padding:6px 14px;border-radius:999px;background:${p.answer === "non" ? "#efe4e4" : "#e6f1e8"};font:600 13px system-ui,sans-serif}` +
    `p{margin:4px 0;font-size:16px}.ev{margin-top:16px;padding-top:16px;border-top:1px solid #eee}.ev b{display:block;font-size:20px;font-weight:500}` +
    `.ar{margin-top:16px;padding:10px;border-radius:12px;background:#e6f1e8;font:600 14px system-ui,sans-serif}` +
    `footer{margin-top:18px;font:12px system-ui,sans-serif;color:#8a7d6b}</style></head><body><main>` +
    `<div class="eye">Carte d'invité</div><h1>${escapeHtml(String(p.name))}</h1><div class="st">${escapeHtml(status)}</div>` +
    `<div class="ev"><b>${escapeHtml(String(p.title || ""))}</b>${line(p.date_fr)}${line(p.place)}${p.org_name ? line(`Une invitation de ${p.org_name}`) : ""}</div>` +
    (arrived ? `<div class="ar">${escapeHtml(arrived)}</div>` : "") +
    `<footer>Marakaj</footer></main></body></html>`;
  return new Response(html, { headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" } });
}

// ------------------------------------------------------------------ 161
// The ticket pages: plain pages, the same on every phone, never cached.
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const PAY_KIND = { orange: "Orange Money", moov: "Moov Money", wave: "Wave", autre: "Autre" };

function ticketShell(title, body, script) {
  return `<!doctype html><html lang="fr"><head><meta charset="utf-8">` +
    `<meta name="viewport" content="width=device-width, initial-scale=1"><meta name="robots" content="noindex">` +
    `<title>${escapeHtml(title)}</title><style>` +
    `*{box-sizing:border-box}body{margin:0;background:#f4efe6;color:#1a140c;font:16px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif}` +
    `main{max-width:560px;margin:0 auto;padding:24px 16px 48px}` +
    `.card{background:#fff;border-radius:20px;padding:22px 20px;box-shadow:0 20px 60px -30px rgba(0,0,0,.35);margin-bottom:16px}` +
    `.eye{font-size:11px;font-weight:600;letter-spacing:.2em;text-transform:uppercase;color:#8a6d3b}` +
    `h1{font:500 28px/1.15 Georgia,"Times New Roman",serif;margin:8px 0 6px}h2{font:600 17px/1.3 system-ui,sans-serif;margin:0 0 10px}` +
    `.muted{color:#6f6556;font-size:14px}.row{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:12px 0;border-top:1px solid #eee}` +
    `.row:first-of-type{border-top:0}.price{font-weight:700;white-space:nowrap}` +
    `.qty{display:flex;align-items:center;gap:8px}.qty button{width:36px;height:36px;border-radius:50%;border:1px solid #d9d1c3;background:#fff;font-size:18px;cursor:pointer}` +
    `.qty b{min-width:22px;text-align:center}label{display:block;font-size:13px;font-weight:600;margin:14px 0 6px}` +
    `input{width:100%;font:inherit;padding:12px 14px;border:1px solid #d9d1c3;border-radius:12px;background:#fff}` +
    `.btn{display:block;width:100%;text-align:center;padding:15px 18px;border:0;border-radius:999px;background:#1a140c;color:#fff;font:600 15px system-ui,sans-serif;text-decoration:none;cursor:pointer;margin-top:14px}` +
    `.btn.ghost{background:#fff;color:#1a140c;border:1px solid #1a140c}.btn.wa{background:#1f8f4e}.btn:disabled{opacity:.5}` +
    `.pay{padding:12px 14px;border-radius:14px;background:#f7f2ea;margin:8px 0}.pay b{display:block}` +
    `.big{font:700 22px/1.2 system-ui,sans-serif}.ref{font:700 20px ui-monospace,Menlo,monospace;letter-spacing:.08em}` +
    `.tag{display:inline-block;padding:5px 12px;border-radius:999px;font-size:13px;font-weight:600;background:#efe7d6}` +
    `.ok{background:#e6f1e8;color:#1d5b33}.no{background:#f4e1e1;color:#7a2424}` +
    `.qr{width:220px;height:220px;margin:12px auto}.qr svg{width:100%;height:100%}.ticket{text-align:center;padding:18px 0;border-top:1px dashed #d9d1c3}` +
    `.err{color:#8a1f1f;font-size:14px;margin-top:10px;min-height:1em}.note{font-size:12px;color:#8a7d6b;margin-top:18px;text-align:center}` +
    `</style></head><body><main>${body}<p class="note">Le paiement se fait directement à l’organisateur. Marakaj n’encaisse rien.</p></main>` +
    (script ? `<script>${script}</script>` : "") + `</body></html>`;
}

function ticketResponse(html, status = 200) {
  return new Response(html, { status, headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" } });
}

function moneyText(n, currency) {
  const v = Math.round(Number(n) || 0).toString().replace(/\B(?=(\d{3})+(?!\d))/g, "\u202f");
  return `${v} ${currency === "XOF" || currency === "XAF" || !currency ? "FCFA" : currency}`;
}

function waDigits(raw) {
  let d = String(raw || "").replace(/\D/g, "");
  if (d.startsWith("00")) d = d.slice(2);
  if (d.length === 8) d = `226${d}`;
  return /^\d{10,15}$/.test(d) ? d : null;
}

function jsonForScript(value) {
  return JSON.stringify(value).replace(/</g, "\\u003c").replace(/[\u2028\u2029]/g, "");
}

// /e/<slug>/billets — the ticket types, how many of each, a name and a
// WhatsApp, the request sent to event_ticket_request.
export async function ticketsPage(env, slug, preview) {
  if (!env.SUPABASE_URL || !env.SUPABASE_PUBLISHABLE_KEY) return ticketResponse(ticketShell("Billets", `<div class="card"><h2>La billetterie n’est pas disponible.</h2></div>`), 404);
  let o = null;
  try { o = await rpcFresh(env, "event_ticket_offer", { p_slug: slug, p_preview: preview || "" }); } catch (_) { o = null; }
  if (!o || o.on !== true) return ticketResponse(ticketShell("Billets", `<div class="card"><h2>Cet événement ne vend pas de billets.</h2></div>`), 404);
  const types = Array.isArray(o.types) ? o.types : [];
  const rows = types.map((t) => {
    const out = t.left === 0;
    return `<div class="row" data-type="${escapeHtml(t.id)}" data-price="${Number(t.price) || 0}" data-left="${t.left == null ? "" : t.left}">` +
      `<div><b>${escapeHtml(t.name)}</b><div class="muted">${escapeHtml(moneyText(t.price, o.currency))}` +
      `${t.left == null ? "" : out ? " · Complet" : t.left <= 20 ? ` · Plus que ${t.left} place${t.left > 1 ? "s" : ""}` : ""}</div></div>` +
      (out ? `<span class="tag no">Complet</span>` : `<div class="qty"><button type="button" data-d="-1" aria-label="Un de moins">−</button><b>0</b><button type="button" data-d="1" aria-label="Un de plus">+</button></div>`) +
      `</div>`;
  }).join("");
  const body =
    `<div class="card"><div class="eye">Billetterie</div><h1>${escapeHtml(o.title || "")}</h1>` +
    `<div class="muted">${escapeHtml([o.date_fr, o.place].filter(Boolean).join(" · "))}</div>` +
    (o.org_name ? `<div class="muted">Organisé par ${escapeHtml(o.org_name)}</div>` : "") + `</div>` +
    (o.open === false
      ? `<div class="card"><h2>La vente des billets est terminée.</h2></div>`
      : `<form class="card" id="f" novalidate><h2>Vos billets</h2>${rows || `<p class="muted">Aucun billet en vente pour le moment.</p>`}` +
        `<div class="row"><b>Total</b><span class="price big" id="total">${escapeHtml(moneyText(0, o.currency))}</span></div>` +
        `<label for="n">Votre nom</label><input id="n" autocomplete="name" maxlength="80" required>` +
        `<label for="w">Votre WhatsApp</label><input id="w" inputmode="tel" autocomplete="tel" maxlength="24" placeholder="+226 70 00 00 00" required>` +
        `<label for="t">Numéro de transaction (si vous avez déjà payé)</label><input id="t" maxlength="40" placeholder="Facultatif">` +
        `<button class="btn" type="submit" id="go">Demander mes billets</button><div class="err" id="err" role="alert"></div>` +
        `<p class="muted">Vos places sont gardées ${o.hold_hours} heures, le temps de payer l’organisateur.</p></form>`);
  const boot = { slug, preview: preview || null, currency: o.currency, api: { url: env.SUPABASE_URL, key: env.SUPABASE_PUBLISHABLE_KEY } };
  const script = `var B=${jsonForScript(boot)};` + `
(function(){var f=document.getElementById('f');if(!f)return;var q={};
function money(n){return String(Math.round(n)).replace(/\\B(?=(\\d{3})+(?!\\d))/g,'\\u202f')+' '+(B.currency==='XOF'||B.currency==='XAF'?'FCFA':B.currency);}
function sum(){var t=0;Array.prototype.forEach.call(f.querySelectorAll('[data-type]'),function(r){t+=(q[r.dataset.type]||0)*(+r.dataset.price||0);});document.getElementById('total').textContent=money(t);}
Array.prototype.forEach.call(f.querySelectorAll('[data-type]'),function(r){Array.prototype.forEach.call(r.querySelectorAll('button[data-d]'),function(b){b.onclick=function(){var id=r.dataset.type,left=r.dataset.left===''?20:Math.min(20,+r.dataset.left),v=Math.max(0,Math.min(left,(q[id]||0)+(+b.dataset.d)));q[id]=v;r.querySelector('.qty b').textContent=v;sum();};});});
f.onsubmit=function(e){e.preventDefault();var err=document.getElementById('err'),go=document.getElementById('go');err.textContent='';
var lines=Object.keys(q).filter(function(k){return q[k]>0;}).map(function(k){return {type:k,qty:q[k]};});
if(!lines.length){err.textContent='Choisissez au moins un billet.';return;}
var n=document.getElementById('n').value.trim(),w=document.getElementById('w').value.trim(),t=document.getElementById('t').value.trim();
if(!n){err.textContent='Votre nom, s’il vous plaît.';return;}if(w.replace(/\\D/g,'').length<6){err.textContent='Votre numéro WhatsApp, pour que l’organisateur vous réponde.';return;}
go.disabled=true;go.textContent='Envoi…';
fetch(B.api.url.replace(/\\/+$/,'')+'/rest/v1/rpc/event_ticket_request',{method:'POST',headers:{'Content-Type':'application/json',apikey:B.api.key,Authorization:'Bearer '+B.api.key},
body:JSON.stringify({p_slug:B.slug,p_preview:B.preview,p_name:n,p_whatsapp:w,p_lines:lines,p_txn:t||null})}).then(function(r){return r.json().then(function(j){return {ok:r.ok,j:j};});})
.then(function(x){if(!x.ok||!x.j||!x.j.id){throw new Error((x.j&&(x.j.message||x.j.hint))||'La demande n’est pas passée.');}
try{var s=JSON.parse(localStorage.getItem('mk-billets')||'[]');s.push({slug:B.slug,id:x.j.id});localStorage.setItem('mk-billets',JSON.stringify(s.slice(-20)));}catch(e2){}
location.href='/e/'+encodeURIComponent(B.slug)+'/billets/'+x.j.id;})
.catch(function(e3){err.textContent=e3.message||'Pas de réseau : réessayez.';go.disabled=false;go.textContent='Demander mes billets';});};})();`;
  return ticketResponse(ticketShell(`Billets · ${o.title || ""}`, body, script));
}

// /e/<slug>/billets/<id> — the buyer's request: where to pay and the
// reference while it waits, the tickets once the organiser has validated.
export async function ticketStatusPage(env, slug, id) {
  const missing = () => ticketResponse(ticketShell("Billets", `<div class="card"><h2>Cette demande de billets n’existe pas.</h2></div>`), 404);
  if (!UUID.test(id)) return missing();
  if (!env.SUPABASE_URL || !env.SUPABASE_PUBLISHABLE_KEY) return missing();
  let r = null;
  try { r = await rpcFresh(env, "event_ticket_status", { p_id: id }); } catch (_) { r = null; }
  if (!r || !r.id || r.slug !== slug) return missing();
  const lines = (r.lines || []).map((l) => `${l.qty} × ${escapeHtml(l.name)}`).join(" · ");
  const head = `<div class="card"><div class="eye">Vos billets</div><h1>${escapeHtml(r.title || "")}</h1>` +
    `<div class="muted">${escapeHtml([r.date_fr, r.place].filter(Boolean).join(" · "))}</div>` +
    `<div style="margin-top:12px">${escapeHtml(r.name)} · ${lines} · <b>${escapeHtml(moneyText(r.total, r.currency))}</b></div></div>`;
  const orgWa = waDigits(r.pay_whatsapp);
  let body = head;
  if (r.status === "pending") {
    const pays = (r.pay_methods || []).map((p) => `<div class="pay"><b>${escapeHtml(PAY_KIND[p.kind] || p.kind || "")}</b>` +
      `${escapeHtml(p.number || "")}${p.name ? ` · ${escapeHtml(p.name)}` : ""}</div>`).join("");
    const waText = `Bonjour, j’ai demandé des billets pour « ${r.title} » : référence ${r.ref}, ${moneyText(r.total, r.currency)}.${r.txn_ref ? ` Transaction : ${r.txn_ref}.` : ""}`;
    const until = new Date(r.hold_until);
    body += `<div class="card"><span class="tag">En attente du paiement</span>` +
      `<h2 style="margin-top:14px">Payez ${escapeHtml(moneyText(r.total, r.currency))} à l’organisateur</h2>${pays || `<p class="muted">L’organisateur vous indiquera où payer.</p>`}` +
      `<p>En indiquant la référence :</p><div class="ref">${escapeHtml(r.ref)}</div>` +
      `<p class="muted">Vos places sont gardées jusqu’au ${escapeHtml(until.toLocaleString("fr-FR", { day: "numeric", month: "long", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Ouagadougou" }))}. Une fois le paiement vu par l’organisateur, vos billets apparaissent ici.</p>` +
      (orgWa ? `<a class="btn wa" href="https://wa.me/${orgWa}?text=${encodeURIComponent(waText)}" target="_blank" rel="noopener">Écrire à l’organisateur sur WhatsApp</a>` : "") +
      `<form id="tx" novalidate><label for="t">Votre numéro de transaction</label><input id="t" maxlength="40" value="${escapeHtml(r.txn_ref || "")}" placeholder="Celui du SMS de paiement">` +
      `<button class="btn ghost" type="submit">Envoyer le numéro</button><div class="err" id="err" role="status"></div></form>` +
      `<a class="btn ghost" href="">Actualiser</a></div>`;
  } else if (r.status === "paid") {
    body += `<div class="card"><span class="tag ok">Payé · ${(r.tickets || []).length} billet${(r.tickets || []).length > 1 ? "s" : ""}</span>` +
      (r.tickets || []).map((k, i) => `<div class="ticket"><div class="eye">Billet ${i + 1} · ${escapeHtml(k.type)}</div>` +
        `<div class="qr" data-qr="${SITE}/e/${encodeURIComponent(slug)}/billet/${escapeHtml(k.id)}"></div>` +
        `<b>${escapeHtml(k.holder)}</b><div class="muted">${k.status === "used" ? "Déjà utilisé" : k.status === "void" ? "Annulé" : "Valable une fois, à présenter à l’entrée"}</div></div>`).join("") +
      `<a class="btn" href="/billets/${escapeHtml(r.id)}">Garder mes billets dans Marakaj</a>` +
      `<p class="muted" style="text-align:center">Gardés dans votre compte, ils s’ouvrent même sans connexion.</p></div>`;
  } else {
    const word = r.status === "refused" ? "Demande refusée par l’organisateur." : r.status === "refunded" ? "Billets remboursés." : "Demande expirée : le paiement n’a pas été vu à temps.";
    body += `<div class="card"><span class="tag no">${escapeHtml(word)}</span>` +
      (orgWa ? `<a class="btn wa" href="https://wa.me/${orgWa}?text=${encodeURIComponent(`Bonjour, au sujet de ma demande ${r.ref} pour « ${r.title} ».`)}" target="_blank" rel="noopener">Écrire à l’organisateur</a>` : "") +
      `<a class="btn ghost" href="/e/${encodeURIComponent(slug)}/billets">Faire une nouvelle demande</a></div>`;
  }
  const boot = { id: r.id, slug, api: { url: env.SUPABASE_URL, key: env.SUPABASE_PUBLISHABLE_KEY } };
  const script = `var B=${jsonForScript(boot)};` + `
try{var s=JSON.parse(localStorage.getItem('mk-billets')||'[]');if(!s.some(function(x){return x.id===B.id;})){s.push({slug:B.slug,id:B.id});localStorage.setItem('mk-billets',JSON.stringify(s.slice(-20)));}}catch(e){}
(function(){var boxes=document.querySelectorAll('[data-qr]');if(boxes.length){var s=document.createElement('script');s.src='https://cdnjs.cloudflare.com/ajax/libs/qrcode-generator/1.4.4/qrcode.min.js';
s.onload=function(){Array.prototype.forEach.call(boxes,function(b){try{var q=qrcode(0,'M');q.addData(b.dataset.qr);q.make();b.innerHTML=q.createSvgTag({cellSize:4,margin:0,scalable:true});}catch(e){b.textContent='QR';}});};document.head.appendChild(s);}
var f=document.getElementById('tx');if(!f)return;f.onsubmit=function(e){e.preventDefault();var err=document.getElementById('err'),t=document.getElementById('t').value.trim();if(!t){err.textContent='Le numéro du SMS de paiement.';return;}
fetch(B.api.url.replace(/\\/+$/,'')+'/rest/v1/rpc/event_ticket_txn',{method:'POST',headers:{'Content-Type':'application/json',apikey:B.api.key,Authorization:'Bearer '+B.api.key},body:JSON.stringify({p_id:B.id,p_txn:t})})
.then(function(r){err.textContent=r.ok?'Numéro envoyé à l’organisateur.':'Le numéro n’est pas passé.';},function(){err.textContent='Pas de réseau : réessayez.';});};})();`;
  return ticketResponse(ticketShell(`Billets · ${r.title || ""}`, body, script));
}

// /e/<slug>/billet/<id> — one ticket, as its QR opens it for whoever holds
// it: whose, which, still valid or used. The door's app checks it for real.
export async function ticketPage(env, slug, id) {
  const missing = () => ticketResponse(ticketShell("Billet", `<div class="card"><h2>Ce billet n’existe pas.</h2></div>`), 404);
  if (!UUID.test(id) || !env.SUPABASE_URL || !env.SUPABASE_PUBLISHABLE_KEY) return missing();
  let k = null;
  try { k = await rpcFresh(env, "event_ticket_view", { p_slug: slug, p_id: id }); } catch (_) { k = null; }
  if (!k || !k.id) return missing();
  const state = k.status === "used" ? `<span class="tag no">Déjà utilisé</span>` : k.status === "void" ? `<span class="tag no">Annulé</span>` : `<span class="tag ok">Valable</span>`;
  const body = `<div class="card" style="text-align:center"><div class="eye">Billet · ${escapeHtml(k.type)}</div><h1>${escapeHtml(k.holder)}</h1>${state}` +
    `<p><b>${escapeHtml(k.title || "")}</b><br><span class="muted">${escapeHtml([k.date_fr, k.place].filter(Boolean).join(" · "))}</span></p>` +
    `<p class="muted">Référence ${escapeHtml(k.ref)}</p></div>`;
  return ticketResponse(ticketShell(`Billet · ${k.title || ""}`, body));
}

// The sample words of a design shown as a card (155c), by the kind of
// event it was drawn for.
const DEMO_KIND = {
  anniv: "anniversaire", bapteme: "bapteme", naissance: "naissance", diplome: "diplome",
  gala: "gala", dot: "dot", hommage: "hommage",
};
const DEMO_TITLE = {
  mariage: "Inès & Thomas", anniversaire: "Les 30 ans de Rokia", bapteme: "Noé", naissance: "Imani",
  diplome: "Promotion 2027", gala: "Gala des Anciens", dot: "Awa & Moussa", hommage: "Papa Jo",
};

// /modele/<key> — a design as the guests would see it, with sample words:
// the answers stay on the phone (demo), the album is away, nothing is
// saved. Cached: the same for everyone.
export async function demoPage(request, env, key) {
  const animated = ANIMATED.test(key);
  if (!animated && !EVENT_CARDS.has(key)) {
    return new Response("Introuvable.", {
      status: 404,
      headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" },
    });
  }
  const kind = DEMO_KIND[key] || "mariage";
  const starts = new Date(Date.now() + 45 * 864e5);
  starts.setUTCHours(15, 0, 0, 0);
  const data = {
    slug: `modele-${key}`,
    kind,
    card: key,
    family: animated ? "anime" : "classique",
    premium: /_p$/.test(key),
    title: DEMO_TITLE[kind] || DEMO_TITLE.mariage,
    starts_at: starts.toISOString(),
    tz: "Africa/Ouagadougou",
    place: "Villa Serena, Ouagadougou",
    content: {},
    rsvp_on: true,
    album_on: false,
    published: false,
    org_name: "",
  };
  return cardPage(request, env, { slug: data.slug, data, preview: null, edit: null, editor: false, demo: true });
}

// The card's page, the event written in: /e/<slug> (152) and the designs'
// samples (/modele/<key>, 155c) share it.
async function cardPage(request, env, { slug, data, preview, edit, editor, demo }) {
  const gone = () => new Response("Cette carte n'est pas ouverte.", {
    status: 404,
    headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" },
  });
  // Two families of design (153): the twelve cards under /cartes, each its
  // own page; the animated layouts, one page under /evenements that draws
  // the layout the event names (window.CARTE.lay).
  const animated = data.family === "anime" || ANIMATED.test(String(data.card || ""));
  const card = animated
    ? (ANIMATED.test(String(data.card || "")) ? String(data.card) : "anime_lettre")
    : (EVENT_CARDS.has(data.card) ? data.card : "come");
  const base = animated ? "/evenements/" : "/cartes/";
  const page = await assetPage(env, request, animated ? "/evenements/index.html" : `/cartes/${card}.html`);
  if (!page.ok) return gone();

  // The day and hour on the organiser's clock (events.tz, 153): the
  // animated page composes its own date from them.
  const when = localParts(data.starts_at, data.tz);
  const boot = {
    slug: data.slug,
    kind: data.kind,
    card,
    family: animated ? "anime" : "classique",
    premium: data.premium === true,
    lay: animated ? card.slice("anime_".length) : null,
    title: data.title,
    starts_at: data.starts_at || null,
    tz: data.tz || null,
    date: when.date,
    time: when.time,
    place: data.place || null,
    content: data.content && typeof data.content === "object" ? data.content : {},
    rsvp_on: data.rsvp_on !== false,
    album_on: data.album_on !== false,
    tickets: data.tickets === true,
    published: data.published === true,
    org_name: data.org_name || "",
    preview: preview || null,
    // The organiser's editor (154): the token it saves with, and where its
    // pictures go and come from.
    editor,
    edit: editor ? edit : null,
    uploads: env.UPLOADS_URL ? env.UPLOADS_URL.replace(/\/$/, "") : null,
    // A design's sample (155c): the page keeps the answers on the phone.
    demo,
    api: { url: env.SUPABASE_URL || null, key: env.SUPABASE_PUBLISHABLE_KEY || null },
  };
  // Safe inside <script>: no « < » (so no « </script> »), no line separators.
  const json = JSON.stringify(boot).replace(/</g, "\\u003c").replace(/[\u2028\u2029]/g, "");
  const title = `${data.title} · Marakaj`;
  const description = clip([
    data.place,
    data.org_name ? `Une invitation de ${data.org_name}` : "Une invitation sur Marakaj",
  ].filter(Boolean).join(" · "), 160);

  const rewritten = new HTMLRewriter()
    .on("title", { element(e) { e.setInnerContent(title); } })
    .on("head", {
      element(e) {
        // The page's stylesheet, script and pictures are relative to its
        // folder (/cartes/ or /evenements/).
        e.prepend(`<base href="${base}">`, { html: true });
        e.append(
          `<meta property="og:title" content="${escapeHtml(data.title)}">` +
          `<meta property="og:description" content="${escapeHtml(description)}">` +
          `<meta property="og:url" content="${SITE}/${demo ? `modele/${escapeHtml(data.card)}` : `e/${escapeHtml(slug)}`}">` +
          `<meta property="og:type" content="website">` +
          `<meta name="robots" content="noindex">` +
          `<script>window.CARTE=${json}</script>`,
          { html: true },
        );
      },
    })
    .transform(page);
  const headers = new Headers(rewritten.headers);
  headers.set("Cache-Control", demo ? "public, max-age=3600" : "no-store");
  headers.set("Content-Type", "text/html; charset=utf-8");
  return new Response(rewritten.body, { status: 200, headers });
}

// A page of the build, by its file's address. The assets binding answers
// a page's address the way the site is set (html_handling, Cloudflare's
// default auto-trailing-slash): /cartes/come.html sends to /cartes/come,
// /evenements/index.html to /evenements/ — a redirect, which is not the
// page. Followed here, a hop or two; every card and every sample read
// « Cette carte n'est pas ouverte » on the live site before this.
async function assetPage(env, request, path) {
  let url = new URL(path, request.url);
  for (let hop = 0; hop < 3; hop++) {
    const res = await env.ASSETS.fetch(new Request(url.toString(), { method: "GET", headers: { Accept: "text/html" } }));
    const to = res.headers.get("Location");
    if (res.status >= 300 && res.status < 400 && to) {
      url = new URL(to, url);
      continue;
    }
    return res;
  }
  return new Response(null, { status: 404 });
}

// Asked fresh every time (a card is private until published, and the
// organiser expects a change to show at once), unlike the vitrines' rpc.
async function rpcFresh(env, fn, params) {
  const response = await fetch(rpcUrl(env, fn, params), {
    method: "GET",
    headers: {
      apikey: env.SUPABASE_PUBLISHABLE_KEY,
      Authorization: `Bearer ${env.SUPABASE_PUBLISHABLE_KEY}`,
    },
    cache: "no-store",
  });
  if (!response.ok) return null;
  return response.json();
}

function escapeHtml(text) {
  return String(text).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
}

function clip(text, max) {
  const t = String(text).replace(/\s+/g, " ").trim();
  return t.length > max ? `${t.slice(0, max - 1)}…` : t;
}
