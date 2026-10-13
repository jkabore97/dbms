// /api/maps-link?u=<a Google Maps link> — the position a short link hides.
//
// A phone's « Partager » in Google Maps gives `https://maps.app.goo.gl/…`,
// which carries no position: it only redirects. The app cannot follow it
// itself (a browser refuses Google's answer across origins), so it asks
// here. This Worker follows the redirects by hand, ONLY through Google's
// own Maps hosts (anything else is refused, at every hop, so it can never
// be used to reach another address), reads the position from the address
// it lands on — or, when that address has none, from the first 300 kB of
// the page Google answers — and says { lat, lng }, or 404 { error }.
// Nothing is kept or logged but the outcome.

const HOP_LIMIT = 6;
const PAGE_LIMIT = 300_000;

export function allowedMapsHost(url) {
  if (url.protocol !== "https:") return false;
  const host = url.hostname.toLowerCase();
  const path = url.pathname.toLowerCase();
  if (host === "maps.app.goo.gl") return true;
  if (host === "goo.gl" && path.startsWith("/maps")) return true;
  if (host === "g.co" && path.startsWith("/kgs")) return true;
  if (host === "maps.google.com") return true;
  if (/^(www\.)?google\.[a-z]{2,3}(\.[a-z]{2})?$/.test(host)) {
    return path.startsWith("/maps") || path === "/url" || path.startsWith("/search");
  }
  // consent.google.com sends a phone to its cookie page first; its
  // « continue » parameter is the place.
  if (host === "consent.google.com") return true;
  return false;
}

const N = "(-?\\d+(?:\\.\\d+)?)";
const PATTERNS = [
  new RegExp(`@${N},${N}`),
  new RegExp(`!3d${N}!4d${N}`),
  new RegExp(`[?&](?:q|query|ll|sll|center|daddr|destination)=${N}\\s*,\\s*${N}`),
  new RegExp(`/(?:search|place|dir)/${N}\\s*,\\s*${N}`),
];

export function positionIn(text) {
  let s = String(text || "");
  try { s = decodeURIComponent(s); } catch (_) { /* keep it as it came */ }
  s = s.replace(/\+/g, " ");
  for (const p of PATTERNS) {
    const m = s.match(p);
    if (!m) continue;
    const lat = Number(m[1]);
    const lng = Number(m[2]);
    if (Number.isFinite(lat) && Number.isFinite(lng)
        && lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180
        && !(lat === 0 && lng === 0)) {
      return { lat, lng };
    }
  }
  return null;
}

// Google's page embeds the place as [null,null,lat,lng] in its state.
export function positionInPage(html) {
  const direct = positionIn(html);
  if (direct) return direct;
  const m = String(html).match(/\[null,null,(-?\d{1,2}\.\d{3,}),(-?\d{1,3}\.\d{3,})\]/);
  if (m) {
    const lat = Number(m[1]);
    const lng = Number(m[2]);
    if (lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180) return { lat, lng };
  }
  return null;
}

function answer(body, status) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": status === 200 ? "public, max-age=86400" : "no-store",
    },
  });
}

export async function mapsLink(request, fetchImpl = fetch) {
  const raw = new URL(request.url).searchParams.get("u") || "";
  let url;
  try {
    url = new URL(raw.trim());
  } catch (_) {
    return answer({ error: "bad link" }, 400);
  }
  if (!allowedMapsHost(url)) return answer({ error: "not a Google Maps link" }, 400);

  for (let hop = 0; hop < HOP_LIMIT; hop++) {
    const found = positionIn(url.href);
    if (found) return answer(found, 200);
    if (url.hostname === "consent.google.com") {
      const next = url.searchParams.get("continue");
      if (!next) break;
      try { url = new URL(next); } catch (_) { break; }
      if (!allowedMapsHost(url)) return answer({ error: "left Google Maps" }, 400);
      continue;
    }
    let response;
    try {
      response = await fetchImpl(url.href, {
        redirect: "manual",
        headers: {
          "User-Agent": "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36",
          "Accept-Language": "fr,en;q=0.8",
        },
      });
    } catch (_) {
      return answer({ error: "unreachable" }, 502);
    }
    const location = response.headers.get("Location");
    if (response.status >= 300 && response.status < 400 && location) {
      let next;
      try { next = new URL(location, url); } catch (_) { break; }
      if (!allowedMapsHost(next)) return answer({ error: "left Google Maps" }, 400);
      url = next;
      continue;
    }
    if (response.status === 200) {
      const text = (await response.text()).slice(0, PAGE_LIMIT);
      const inPage = positionInPage(text);
      if (inPage) return answer(inPage, 200);
    }
    break;
  }
  return answer({ error: "no position" }, 404);
}
