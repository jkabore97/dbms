// Cloudflare Worker: the only thing that may write to the photo bucket.
//
// M5's camera button needs somewhere to put bytes. The options were a
// pre-signed URL handed out by something that holds an R2 key, or a Worker
// that holds the key and never hands it out. This is the second, because the
// first still needs a server to decide who may have a URL, and once that
// server exists the pre-signing buys nothing but a second moving part.
//
// The rule this file exists to enforce:
//
//   **Nothing here decides who may do what.** Every authorisation question is
//   forwarded to Postgres and answered by the same RLS policies that guard
//   the tables. The Worker asks "can this token see this org?" by *doing the
//   select as that token* and looking at whether a row comes back. It holds
//   no service-role key, so there is nothing here that could answer wrongly
//   and be believed.
//
// That matters more than usual here: the bucket is one namespace shared by
// every business on the platform, and it has no row-level security of its
// own. `org/<org_id>/…` is the whole of the tenancy model in R2, so the
// prefix is checked on the way in (the caller proved membership of that org)
// and on the way out (a documents row for that key came back under the
// caller's own token, which it only does if the select policy allowed it).
//
// Bindings, see wrangler.toml:
//   UPLOADS                     R2 bucket kaj-app-uploads
//   SUPABASE_URL                the project URL — public, it is in the app
//   SUPABASE_PUBLISHABLE_KEY    the anon key — public, it is in the app too
//   ALLOWED_ORIGINS             comma-separated, the sites that may call this

const MAX_BYTES = 12 * 1024 * 1024;

// What a phone camera actually produces, plus the PDF an invoice arrives as.
// An allowlist rather than a blocklist: the bucket is served back to browsers
// and an uploaded .html or .svg served from this origin would be script
// running as this Worker's site.
const ALLOWED_TYPES = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/heic",
  "image/heif",
  "application/pdf",
]);

const EXTENSIONS = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
  "image/heic": "heic",
  "image/heif": "heif",
  "application/pdf": "pdf",
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export default {
  async fetch(request, env) {
    const origin = request.headers.get("Origin");
    const cors = corsHeaders(origin, env);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }

    const url = new URL(request.url);

    try {
      // POST /v1/orgs/<org_id>/uploads — the camera button.
      const upload = url.pathname.match(/^\/v1\/orgs\/([^/]+)\/uploads$/);
      if (upload && request.method === "POST") {
        return withCors(await put(request, env, upload[1]), cors);
      }

      // GET /v1/objects/<key> — the gallery, and the full-size view.
      const object = url.pathname.match(/^\/v1\/objects\/(.+)$/);
      if (object && (request.method === "GET" || request.method === "HEAD")) {
        return withCors(await get(request, env, decodeURIComponent(object[1])), cors);
      }

      // Something to point a browser at when a deploy is being checked. Says
      // nothing about who is using it.
      if (url.pathname === "/" || url.pathname === "/v1/health") {
        return withCors(json({ ok: true, service: "kaj-uploads" }), cors);
      }

      return withCors(problem(404, "No such route."), cors);
    } catch (err) {
      // Never surface an internal message: it is the one place a bucket name
      // or a binding failure would leak to a caller.
      console.error("uploads worker", err && err.stack ? err.stack : err);
      return withCors(problem(500, "The upload service failed."), cors);
    }
  },
};

// ------------------------------------------------------------
// Writing
// ------------------------------------------------------------

async function put(request, env, orgId) {
  if (!UUID.test(orgId)) {
    return problem(400, "That is not a business id.");
  }

  const token = bearer(request);
  if (!token) {
    return problem(401, "Sign in first.");
  }

  const contentType = (request.headers.get("Content-Type") || "")
    .split(";")[0]
    .trim()
    .toLowerCase();
  if (!ALLOWED_TYPES.has(contentType)) {
    return problem(415, "Photos and PDFs only.");
  }

  // Content-Length is advisory — it is checked again against what actually
  // arrived, below, because a client controls this header.
  const declared = Number(request.headers.get("Content-Length") || 0);
  if (declared > MAX_BYTES) {
    return problem(413, "That file is too large.");
  }

  // The authorisation, in one line: select the org as the caller. RLS returns
  // a row to a member and nothing to anybody else, so a 403 here is the same
  // policy that guards every table.
  if (!(await isMember(env, token, orgId))) {
    return problem(403, "You are not a member of that business.");
  }

  const body = await request.arrayBuffer();
  if (body.byteLength === 0) {
    return problem(400, "There was nothing in the upload.");
  }
  if (body.byteLength > MAX_BYTES) {
    return problem(413, "That file is too large.");
  }

  const now = new Date();
  const key = [
    "org",
    orgId,
    String(now.getUTCFullYear()),
    String(now.getUTCMonth() + 1).padStart(2, "0"),
    `${crypto.randomUUID()}.${EXTENSIONS[contentType]}`,
  ].join("/");

  await env.UPLOADS.put(key, body, {
    httpMetadata: { contentType },
    // Enough to trace an object back to a business without reading Postgres,
    // which is what you want at 2am when a bucket is filling up.
    customMetadata: { orgId },
  });

  // The app records this key with record_document(). Until it does, the
  // object is unreferenced — a lifecycle rule on the bucket is the right
  // place to sweep those, not this Worker, which must not be able to delete.
  return json({ key, bytes: body.byteLength, contentType }, 201);
}

// ------------------------------------------------------------
// Reading
// ------------------------------------------------------------

async function get(request, env, key) {
  const token = bearer(request);
  if (!token) {
    return problem(401, "Sign in first.");
  }

  if (!key.startsWith("org/")) {
    return problem(404, "No such object.");
  }

  // Authorised by the documents row, not by the key: whoever may read the
  // record may read the picture. That is one rule in one place — including
  // 006's rule that an observer entitled to totals is not entitled to the
  // paperwork behind them, which nothing in this file needed to know about.
  if (!(await mayReadDocument(env, token, key))) {
    // 404 rather than 403: a 403 confirms the object exists, which tells a
    // caller which keys are real.
    return problem(404, "No such object.");
  }

  const object = await env.UPLOADS.get(key);
  if (!object) {
    return problem(404, "No such object.");
  }

  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set("etag", object.httpEtag);
  // Private: this response is authorised per caller and must never be held by
  // a shared cache in front of the Worker.
  headers.set("Cache-Control", "private, max-age=3600");
  // Belt and braces on the allowlist above. An image served with a type a
  // browser sniffs its way out of is the classic stored-XSS route.
  headers.set("X-Content-Type-Options", "nosniff");
  headers.set("Content-Security-Policy", "default-src 'none'; sandbox");

  if (request.method === "HEAD") {
    return new Response(null, { status: 200, headers });
  }
  return new Response(object.body, { status: 200, headers });
}

// ------------------------------------------------------------
// Asking Postgres, as the caller
// ------------------------------------------------------------

async function isMember(env, token, orgId) {
  const url = `${env.SUPABASE_URL}/rest/v1/orgs?id=eq.${encodeURIComponent(orgId)}&select=id&limit=1`;
  const rows = await postgrest(env, token, url);
  return Array.isArray(rows) && rows.length === 1;
}

async function mayReadDocument(env, token, key) {
  const url =
    `${env.SUPABASE_URL}/rest/v1/documents` +
    `?r2_key=eq.${encodeURIComponent(key)}&select=id&limit=1`;
  const rows = await postgrest(env, token, url);
  return Array.isArray(rows) && rows.length === 1;
}

async function postgrest(env, token, url) {
  const response = await fetch(url, {
    headers: {
      // The anon key names the project; the bearer token is who is asking.
      // PostgREST needs both, and the role in the JWT is what RLS sees.
      apikey: env.SUPABASE_PUBLISHABLE_KEY,
      Authorization: `Bearer ${token}`,
      Accept: "application/json",
    },
  });

  if (!response.ok) {
    // An expired or forged token lands here as a 401 from PostgREST. Treated
    // the same as "no rows": not authorised.
    return null;
  }
  return response.json();
}

// ------------------------------------------------------------
// Plumbing
// ------------------------------------------------------------

function bearer(request) {
  const header = request.headers.get("Authorization") || "";
  const match = header.match(/^Bearer\s+(.+)$/i);
  return match ? match[1].trim() : null;
}

function corsHeaders(origin, env) {
  const allowed = (env.ALLOWED_ORIGINS || "")
    .split(",")
    .map((o) => o.trim())
    .filter(Boolean);

  const headers = {
    "Access-Control-Allow-Methods": "GET, HEAD, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Authorization, Content-Type",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  };

  // No wildcard, ever: this endpoint answers differently depending on who is
  // asking, and a wildcard would let any page a signed-in person opens read
  // their business's photographs.
  if (origin && allowed.includes(origin)) {
    headers["Access-Control-Allow-Origin"] = origin;
  }
  return headers;
}

function withCors(response, cors) {
  const merged = new Headers(response.headers);
  for (const [k, v] of Object.entries(cors)) merged.set(k, v);
  return new Response(response.body, { status: response.status, headers: merged });
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// One shape for every failure, so the app can show `message` and never has to
// parse prose. In French, because it is what the person reads.
const FRENCH = {
  400: "Requête invalide.",
  401: "Connectez-vous d'abord.",
  403: "Vous n'êtes pas membre de cette entreprise.",
  404: "Introuvable.",
  413: "Ce fichier est trop volumineux (12 Mo maximum).",
  415: "Photos et PDF uniquement.",
  500: "Le service de photos a échoué.",
};

function problem(status, detail) {
  return json({ error: FRENCH[status] || detail, detail, status }, status);
}
