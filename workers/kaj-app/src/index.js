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
      return eventPage(request, env, event[1], url.searchParams.get("apercu"));
    }
    // The cards' pages are not addresses of their own: only /e/<slug> is.
    if (/^\/cartes\/[a-z]+\.html$/.test(url.pathname)) {
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
]);

// /e/<slug> — the card page with the event in it (152). Never cached:
// a preview link is private, and the organiser's change shows at once.
export async function eventPage(request, env, slug, preview) {
  const gone = () => new Response("Cette carte n'est pas ouverte.", {
    status: 404,
    headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" },
  });
  if (!env.SUPABASE_URL || !env.SUPABASE_PUBLISHABLE_KEY) return gone();
  let data = null;
  try {
    data = await rpcFresh(env, "event_public", { p_slug: slug, p_preview: preview || "" });
  } catch (_) {
    data = null;
  }
  if (!data || typeof data !== "object" || !data.title) return gone();

  const card = EVENT_CARDS.has(data.card) ? data.card : "come";
  const page = await env.ASSETS.fetch(new Request(new URL(`/cartes/${card}.html`, request.url), request));
  if (!page.ok) return gone();

  const boot = {
    slug: data.slug,
    kind: data.kind,
    card,
    title: data.title,
    starts_at: data.starts_at || null,
    place: data.place || null,
    content: data.content && typeof data.content === "object" ? data.content : {},
    rsvp_on: data.rsvp_on !== false,
    album_on: data.album_on !== false,
    published: data.published === true,
    org_name: data.org_name || "",
    preview: preview || null,
    api: { url: env.SUPABASE_URL, key: env.SUPABASE_PUBLISHABLE_KEY },
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
        // The page's stylesheet, script and pictures are relative to /cartes/.
        e.prepend('<base href="/cartes/">', { html: true });
        e.append(
          `<meta property="og:title" content="${escapeHtml(data.title)}">` +
          `<meta property="og:description" content="${escapeHtml(description)}">` +
          `<meta property="og:url" content="${SITE}/e/${escapeHtml(slug)}">` +
          `<meta property="og:type" content="website">` +
          `<meta name="robots" content="noindex">` +
          `<script>window.CARTE=${json}</script>`,
          { html: true },
        );
      },
    })
    .transform(page);
  const headers = new Headers(rewritten.headers);
  headers.set("Cache-Control", "no-store");
  headers.set("Content-Type", "text/html; charset=utf-8");
  return new Response(rewritten.body, { status: 200, headers });
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
