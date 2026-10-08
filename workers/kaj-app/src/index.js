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
//     reads.
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

import { legalPage } from "./legal.js";

const SITE = "https://marakaj.com";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.hostname.endsWith(".workers.dev")) {
      return Response.redirect(`${SITE}${url.pathname}${url.search}`, 301);
    }

    // The privacy policy and the terms, as plain pages (legal.js).
    if (request.method === "GET") {
      const legal = legalPage(url.pathname);
      if (legal) return legal;
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
  },
};

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
  const title = line ? `${s.name} — ${line}` : `${s.name} — sur Mara`;
  const description = [
    s.blurb && s.blurb !== line ? clip(s.blurb, 160) : null,
    count > 0 ? `${count} article${count > 1 ? "s" : ""} en vitrine` : null,
    "Commandez sur Mara.",
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
    .on("title", { element(e) { e.setInnerContent(`${s.name} · Mara`); } })
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

async function rpc(env, fn, params) {
  const response = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: {
      apikey: env.SUPABASE_PUBLISHABLE_KEY,
      Authorization: `Bearer ${env.SUPABASE_PUBLISHABLE_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(params),
    cf: { cacheTtl: 300 },
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
