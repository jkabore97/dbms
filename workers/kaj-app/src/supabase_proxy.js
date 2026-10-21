// PostgREST through the site's own address (web first load).
//
// The web app (built with SUPABASE_WEB_PROXY=/sb, app/lib/core/net/
// same_origin_rest.dart) asks https://marakaj.com/sb/rest/v1/… instead of
// https://<project>.supabase.co/rest/v1/…: same origin, so the browser sends
// no OPTIONS preflight before each read and reuses the connection the page
// came on. This passes the request on, as it is, to the project named by
// SUPABASE_URL (set by the deploy from the repository's secrets) and the
// answer back, as it is.
//
// What it is not:
//   - an open proxy. Only SUPABASE_URL's own host, only /rest/v1. Anything
//     else under /sb/ is « not found »; the upstream address is never read
//     from the request.
//   - a guard. It adds no key and checks no token: the browser's own apikey
//     and Authorization go through unchanged, and RLS decides, exactly as
//     when the browser calls the project directly.
//   - a cache. Nothing it answers is kept, here or by Cloudflare.
//
// Left direct, on purpose (the app never sends them here):
//   - /auth/v1: Supabase limits token refreshes, verifications and the like
//     per visitor IP address. Through a Worker every visitor would arrive
//     from Cloudflare's address and share one budget.
//   - /realtime/v1: a websocket has no preflight; nothing to gain.
//   - /storage/v1: the app keeps no files in Supabase Storage (photographs go
//     to the uploads Worker).
//
// Unset SUPABASE_URL: « not configured », and the app built without the
// proxy never comes here.

export const PROXY_PREFIX = "/sb";
const ALLOWED = ["/rest/v1"];

// Connection-level headers a proxy must not pass on, either way.
const HOP_BY_HOP = new Set([
  "connection",
  "keep-alive",
  "proxy-authenticate",
  "proxy-authorization",
  "te",
  "trailer",
  "transfer-encoding",
  "upgrade",
]);

export function isProxyPath(pathname) {
  return pathname === PROXY_PREFIX || pathname.startsWith(`${PROXY_PREFIX}/`);
}

// The project's path for [pathname] (/sb/rest/v1/x → /rest/v1/x), or null
// when it is not one this passes on. The URL parser has already resolved
// any « .. », so /sb/rest/v1/../auth/v1 arrives here as /sb/auth/v1.
export function upstreamPath(pathname) {
  if (!isProxyPath(pathname)) return null;
  const rest = pathname.slice(PROXY_PREFIX.length);
  for (const prefix of ALLOWED) {
    if (rest === prefix || rest.startsWith(`${prefix}/`)) return rest;
  }
  return null;
}

function upstreamOrigin(env) {
  const raw = (env.SUPABASE_URL || "").trim();
  if (!raw) return null;
  try {
    const url = new URL(raw);
    if (url.protocol !== "https:" && url.protocol !== "http:") return null;
    return url.origin;
  } catch (_) {
    return null;
  }
}

function plain(status, text) {
  return new Response(text, {
    status,
    headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" },
  });
}

export async function proxySupabase(request, env, fetcher = fetch) {
  const url = new URL(request.url);
  const path = upstreamPath(url.pathname);
  if (path === null) return plain(404, "Introuvable.");
  const origin = upstreamOrigin(env);
  if (!origin) return plain(503, "Serveur non configuré.");

  const headers = new Headers();
  for (const [name, value] of request.headers) {
    const key = name.toLowerCase();
    if (HOP_BY_HOP.has(key)) continue;
    // The site's own: the address it was asked on, Cloudflare's view of the
    // visitor, and the site's cookies — none of them the project's business.
    if (key === "host" || key === "cookie" || key.startsWith("cf-") || key === "x-real-ip") continue;
    headers.append(name, value);
  }

  const init = {
    method: request.method,
    headers,
    redirect: "manual",
    // Never kept by Cloudflare's cache, whatever the answer says.
    cache: "no-store",
  };
  if (request.method !== "GET" && request.method !== "HEAD") {
    // Streamed through, never read into memory here.
    init.body = request.body;
    init.duplex = "half";
  }

  let answer;
  try {
    answer = await fetcher(`${origin}${path}${url.search}`, init);
  } catch (_) {
    return plain(502, "Le serveur ne répond pas.");
  }

  const out = new Headers();
  for (const [name, value] of answer.headers) {
    if (HOP_BY_HOP.has(name.toLowerCase())) continue;
    out.append(name, value);
  }
  return new Response(answer.body, {
    status: answer.status,
    statusText: answer.statusText,
    headers: out,
  });
}
