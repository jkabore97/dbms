// Cloudflare Worker: the only thing that may reset another person's password
// or delete their account.
//
// Those two actions need Supabase's GoTrue Admin API, which needs the
// service-role key — a key that can do anything to anyone and therefore must
// never sit in the Flutter bundle, where anyone who opens the site could read
// it. So it lives here, in one Worker secret, and this file is the only code
// that ever uses it.
//
// The rule this file keeps, borrowed wholesale from the uploads Worker:
//
//   **The service-role key performs the action. It never decides who may.**
//   Every authorisation question is forwarded to Postgres and answered by the
//   same helpers the app is gated by — manages_user() before a password reset,
//   can_delete_user() before a deletion — asked by DOING the call as the
//   caller's own token. If Postgres says no, the service-role key is never
//   touched. There is nothing here that could answer wrongly and be believed.
//
// Bindings, see wrangler.toml:
//   SUPABASE_URL                the project URL — public, it is in the app
//   SUPABASE_PUBLISHABLE_KEY    the anon key — public, it is in the app too
//   SUPABASE_SERVICE_ROLE_KEY   the secret; unset means the Worker is dormant
//   ALLOWED_ORIGINS             comma-separated, the sites that may call this

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MIN_PASSWORD = 8;

export default {
  async fetch(request, env) {
    const origin = request.headers.get("Origin");
    const cors = corsHeaders(origin, env);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }

    const url = new URL(request.url);

    try {
      // POST /v1/users/<user_id>/password  — an admin sets a new password.
      const pw = url.pathname.match(/^\/v1\/users\/([^/]+)\/password$/);
      if (pw && request.method === "POST") {
        return withCors(await setPassword(request, env, pw[1]), cors);
      }

      // POST /v1/users/<user_id>/delete    — an admin deletes an account.
      const del = url.pathname.match(/^\/v1\/users\/([^/]+)\/delete$/);
      if (del && request.method === "POST") {
        return withCors(await deleteUser(request, env, del[1]), cors);
      }

      if (url.pathname === "/" || url.pathname === "/v1/health") {
        return withCors(
          json({ ok: true, service: "kaj-account", configured: !!env.SUPABASE_SERVICE_ROLE_KEY }),
          cors,
        );
      }

      return withCors(problem(404, "No such route."), cors);
    } catch (err) {
      // Never surface an internal message: this is the one place a binding
      // failure could leak the shape of the service-role setup to a caller.
      console.error("account worker", err && err.stack ? err.stack : err);
      return withCors(problem(500, "The account service failed."), cors);
    }
  },
};

// ------------------------------------------------------------
// Reset a password
// ------------------------------------------------------------

async function setPassword(request, env, userId) {
  if (!UUID.test(userId)) return problem(400, "That is not a user id.");

  const token = bearer(request);
  if (!token) return problem(401, "Sign in first.");
  if (!env.SUPABASE_SERVICE_ROLE_KEY) return problem(501, "Not configured.");

  let body;
  try {
    body = await request.json();
  } catch {
    return problem(400, "Send JSON: {password}.");
  }
  const password = typeof body.password === "string" ? body.password : "";
  if (password.length < MIN_PASSWORD) {
    return problem(422, `Le mot de passe doit faire au moins ${MIN_PASSWORD} caractères.`);
  }

  // The authorisation, forwarded to Postgres as the caller: may you manage this
  // user? A platform admin, or an admin of a business they belong to — decided
  // by 044's manages_user(), the same function the app is gated by.
  if (!(await rpcBool(env, token, "manages_user", { p_user_id: userId }))) {
    return problem(403, "Vous ne gérez pas ce compte.");
  }

  const res = await admin(env, "PUT", userId, { password });
  if (!res.ok) {
    console.error("gotrue set-password", res.status, await res.text());
    return problem(502, "Le changement de mot de passe a échoué.");
  }
  return json({ ok: true });
}

// ------------------------------------------------------------
// Delete an account
// ------------------------------------------------------------

async function deleteUser(request, env, userId) {
  if (!UUID.test(userId)) return problem(400, "That is not a user id.");

  const token = bearer(request);
  if (!token) return problem(401, "Sign in first.");
  if (!env.SUPABASE_SERVICE_ROLE_KEY) return problem(501, "Not configured.");

  // Stricter than a password reset — deletion is global — and 044's
  // can_delete_user() carries every guard: never an owner, never yourself, and
  // for a business admin never someone who also belongs to a business you do
  // not administer.
  if (!(await rpcBool(env, token, "can_delete_user", { p_user_id: userId }))) {
    return problem(403, "Ce compte ne peut pas être supprimé.");
  }

  const res = await admin(env, "DELETE", userId, null);
  // GoTrue answers 200 with the deleted user, or 404 if it was already gone —
  // which is the same end state, so treat it as done.
  if (!res.ok && res.status !== 404) {
    console.error("gotrue delete", res.status, await res.text());
    return problem(502, "La suppression du compte a échoué.");
  }
  return json({ ok: true });
}

// ------------------------------------------------------------
// The GoTrue Admin API — the only use of the service-role key
// ------------------------------------------------------------

function admin(env, method, userId, body) {
  return fetch(`${env.SUPABASE_URL}/auth/v1/admin/users/${encodeURIComponent(userId)}`, {
    method,
    headers: {
      apikey: env.SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
      "Content-Type": "application/json",
    },
    body: body ? JSON.stringify(body) : undefined,
  });
}

// ------------------------------------------------------------
// Asking Postgres, as the caller
// ------------------------------------------------------------

async function rpcBool(env, token, fn, params) {
  const res = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: {
      apikey: env.SUPABASE_PUBLISHABLE_KEY,
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    body: JSON.stringify(params),
  });
  if (!res.ok) return false; // an expired or forged token lands here; not authorised
  const value = await res.json();
  return value === true;
}

// ------------------------------------------------------------
// Plumbing (mirrors the uploads Worker)
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
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Authorization, Content-Type",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  };
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

const FRENCH = {
  400: "Requête invalide.",
  401: "Connectez-vous d'abord.",
  403: "Action non autorisée.",
  404: "Introuvable.",
  422: "Mot de passe trop court.",
  500: "Le service de comptes a échoué.",
  501: "La gestion des comptes n'est pas encore configurée.",
  502: "L'opération a échoué. Réessayez.",
};

function problem(status, detail) {
  return json({ error: FRENCH[status] || detail, detail, status }, status);
}
