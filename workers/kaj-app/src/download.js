// /telecharger (and /download) — one link to share for the app, whatever
// the phone: an Android phone goes straight to Google Play, an iPhone or
// iPad straight to the App Store, and anything else (a computer, WhatsApp's
// link preview) gets a small page with both buttons.
//
// The addresses are the platform's own (122's app_store_links(), set in the
// console's Réglages), read live and kept a minute in this Worker. Supabase
// down, or a value not set there yet: the listings as published — Google
// Play's bf.kaj.app and the App Store's id6821171857. Never a 500.

import { escape, sitePage } from "./legal.js";

export const PLAY_URL = "https://play.google.com/store/apps/details?id=bf.kaj.app";
export const APP_STORE_URL = "https://apps.apple.com/app/id6821171857";
export const DEFAULT_LINKS = Object.freeze({ android: PLAY_URL, ios: APP_STORE_URL });

export function isDownloadPath(path) {
  return /^\/(telecharger|download)\/?$/.test(path);
}

/** "android", "ios" or null, from the User-Agent. */
export function phoneOf(userAgent) {
  const ua = String(userAgent || "");
  if (/android/i.test(ua)) return "android";
  if (/iphone|ipad|ipod/i.test(ua)) return "ios";
  return null;
}

const STORE = /^https:\/\/(play\.google\.com|apps\.apple\.com)\//;

/** What app_store_links() said, kept only when it is a store's address. */
export function linksFrom(value) {
  const v = value && typeof value === "object" && !Array.isArray(value) ? value : {};
  const android = typeof v.android === "string" ? v.android.trim() : "";
  const ios = typeof v.ios === "string" ? v.ios.trim() : "";
  return {
    android: v.android_store === true && STORE.test(android) ? android : PLAY_URL,
    ios: STORE.test(ios) ? ios : APP_STORE_URL,
  };
}

const KEPT_MS = 60_000;
const FAILURE_KEPT_MS = 15_000;
let memo = null;

/** Forgets what was kept (tests). */
export function forgetStoreLinks() {
  memo = null;
}

/** The store links, live, else the published ones — never throws. */
export async function storeLinks(env, now = Date.now()) {
  if (memo && now - memo.at < memo.kept) return memo.value;
  if (!env.SUPABASE_URL || !env.SUPABASE_PUBLISHABLE_KEY) return DEFAULT_LINKS;
  const failed = () => {
    memo = { at: now, kept: FAILURE_KEPT_MS, value: DEFAULT_LINKS };
    return DEFAULT_LINKS;
  };
  try {
    const response = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/app_store_links`, {
      method: "POST",
      headers: {
        apikey: env.SUPABASE_PUBLISHABLE_KEY,
        Authorization: `Bearer ${env.SUPABASE_PUBLISHABLE_KEY}`,
        "Content-Type": "application/json",
      },
      body: "{}",
      signal: AbortSignal.timeout(3000),
    });
    if (!response.ok) return failed();
    const value = linksFrom(await response.json());
    memo = { at: now, kept: KEPT_MS, value };
    return value;
  } catch (_) {
    return failed();
  }
}

export async function downloadPage(request, env) {
  const links = await storeLinks(env);
  const phone = phoneOf(request.headers.get("User-Agent"));
  if (phone) {
    return new Response(null, {
      status: 302,
      headers: { Location: links[phone], "Cache-Control": "no-store", Vary: "User-Agent" },
    });
  }
  return new Response(downloadHtml(links), {
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
      Vary: "User-Agent",
    },
  });
}

const TITLE = "Télécharger Marakaj";
const DESCRIPTION =
  "Marakaj pour Android et iPhone : votre boutique, votre ferme ou votre association, avec sa vitrine en ligne. Gratuit pour commencer.";

export function downloadHtml(links) {
  const head = `<meta property="og:title" content="${escape(TITLE)}">
<meta property="og:description" content="${escape(DESCRIPTION)}">
<meta property="og:image" content="https://marakaj.com/brand/og.jpg">
<meta property="og:url" content="https://marakaj.com/telecharger">
<meta property="og:type" content="website">
`;
  const style = `  .stores { display: flex; flex-wrap: wrap; gap: 12px; margin: 24px 0; }
  .stores a { flex: 1 1 220px; display: block; text-align: center; padding: 14px 18px; border-radius: 12px; background: #0E0D0C; color: #F4F2EE; text-decoration: none; font-weight: 700; }
  .stores a small { display: block; font-weight: 400; font-size: 13px; opacity: .8; }
`;
  const main = `<h1>${escape(TITLE)}</h1>
<p>${escape(DESCRIPTION)}</p>
<div class="stores">
<a href="${escape(links.android)}"><small>Disponible sur</small>Google Play</a>
<a href="${escape(links.ios)}"><small>Télécharger dans</small>l’App Store</a>
</div>
<p>Sur un téléphone, ce lien ouvre directement le bon magasin d’applications. Vous pouvez aussi utiliser Marakaj dans le navigateur : <a href="/">marakaj.com</a>.</p>`;
  return sitePage({ title: TITLE, description: DESCRIPTION, main, head, style });
}
