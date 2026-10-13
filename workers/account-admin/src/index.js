// Cloudflare Worker: the only thing that may reset another person's password
// or delete their account — or, since 113, let a person delete their own
// (« Supprimer mon compte », POST /v1/me/delete).
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
//   And for « Supprimer mon compte » (130):
//   PLAY_SERVICE_ACCOUNT_JSON   revokes a deleted business's Google Play
//                               subscription (workers/pay/src/google.js)
//   STRIPE_SECRET_KEY           cancels its card subscription
//                               — each needed only when there is one to
//                               stop: without it that deletion is refused
//                               and nothing is deleted (review B1)
//   APPLE_SIGNIN_KEY_ID, APPLE_SIGNIN_PRIVATE_KEY
//                               the Sign in with Apple key, to revoke the
//                               person's Apple token (team APPLE_TEAM_ID,
//                               client APPLE_SIGNIN_CLIENT_ID) — optional:
//                               without it that step is logged, the rest
//                               done
//   APPLE_WEB_SERVICES_ID       139: the website's Services ID (default
//                               bf.kaj.app.web), whose codes the website's
//                               Apple popup gives

import { googleRevoke } from "../../pay/src/google.js";
import { signEs256 } from "../../pay/src/jwt.js";

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

      // POST /v1/me/delete                 — a person deletes their own (113).
      if (url.pathname === "/v1/me/delete" && request.method === "POST") {
        return withCors(await deleteMe(request, env), cors);
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
  // user? A platform admin, or an admin above them in a business they belong
  // to — and, since 127, never somebody who also belongs to a business the
  // caller does not administer — decided by manages_user(), the same function
  // the app is gated by.
  if (!(await rpcBool(env, token, "manages_user", { p_user_id: userId }))) {
    return problem(403, "Vous ne gérez pas ce compte.");
  }
  // The platform's own people are nobody's to reset from here — the database
  // says so too (103's manages_user); this is the second lock, read with the
  // service-role key because it is a fact about the target, not a decision.
  if (await isPlatformAdmin(env, userId)) {
    return problem(403, "Ce compte ne se gère pas ici.");
  }

  // email_confirm: true is what makes the reset actually usable. GoTrue will
  // accept the new password on an unconfirmed account and answer 200 — but then
  // refuse the sign-in that uses it with "email not confirmed", which looks
  // exactly like a password that does not work. Most people here get their
  // account from a manager's code and never click a confirmation link, so their
  // email sits unconfirmed. An admin setting a password is vouching for the
  // account, so we confirm it in the same call. Sign-in is by email, so it is
  // the email that has to be confirmed; a phoneless/emailless edge stays a 502.
  const res = await admin(env, "PUT", userId, { password, email_confirm: true });
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
  if (await isPlatformAdmin(env, userId)) {
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
// Delete one's own account (« Supprimer mon compte », 113, for real 130)
// ------------------------------------------------------------

// A deletion needs a sign-in younger than this (review S8): a session
// found on a lost phone, or a token from a log, cannot purge businesses.
export const FRESH_SIGN_IN_SECONDS = 600;

// Google Play and the App Store ask that a person can delete their account
// from the app — every account (130): a shopper, a courier, a member of a
// business, its owner. Postgres decides and does; since review B1 the
// deletion is this Worker's alone (128's section 8 is the service role's,
// never the app's), in an order that holds whatever fails:
//
//   0. who: GoTrue, from the person's own token (whoAmI) — the only id
//      ever used; that token signed in less than ten minutes ago (S8),
//      else 401 « reauth » and the app asks the person to sign in again;
//      never a platform account (read with the key, fail-closed);
//   1. delete_my_account_stops(me, the list the app showed): the
//      database's refusals in French (an open order, a delivery on the
//      road, a payout Mara still owes, a list that changed…), else what
//      will go and what must be stopped outside — nothing changed yet;
//   2. every Stripe subscription cancelled and every Google Play purchase
//      revoked, for each business that will go. One failure, or the key
//      it needs not set (STRIPE_SECRET_KEY, PLAY_SERVICE_ACCOUNT_JSON):
//      stop here, nothing deleted, « Nous n'avons pas pu arrêter
//      l'abonnement … Réessayez dans un moment ou écrivez à l'aide. »;
//   3. account_deletion_note(): the ids stopped, written in
//      account_deletion_log (it outlives the account and the businesses)
//      before anything is purged — and in this Worker's log;
//   4. delete_my_account(me, list, what was stopped): checks nothing still
//      running was left (one started since 1 refuses it), then the
//      database's part in one transaction — the businesses the person
//      alone owns archived and purged (members become plain shoppers,
//      customers told; Mara's own Wave payments kept, detached), the
//      person's own rows gone, their name off what they wrote;
//   5. Sign in with Apple: a person who signed in with Apple has Apple's
//      token revoked (POST appleid.apple.com/auth/revoke, with a client
//      secret signed by the Sign in with Apple key APPLE_SIGNIN_KEY_ID +
//      APPLE_SIGNIN_PRIVATE_KEY, team 9K236BL7SX, client bf.kaj.app),
//      from the fresh authorization code the iPhone app sends
//      (apple_authorization_code). No key, or no code: logged, the rest
//      done. 139: a code from the website's popup belongs to the Services
//      ID (APPLE_WEB_SERVICES_ID), not to bf.kaj.app — the app says whose
//      (apple_client: "web" | "app") and that client id is tried first,
//      the other after it when Apple refuses the code (a code is only
//      valid for the client it was issued to: trying the wrong one first
//      costs a refusal, never the code);
//   6. GoTrue: « hard » deletes the auth user; « soft » (a business's
//      books still name the person, kept for the law as the business's)
//      soft-deletes it (should_soft_delete: e-mail, phone, password,
//      identities and metadata wiped). A hard delete GoTrue refuses is
//      retried soft.
//
// The App Store subscriptions Mara cannot touch: the app told the owner
// to cancel them in their Apple settings, and the answer counts them.
//
// A database still at 127 (no delete_my_account_stops: PostgREST's
// PGRST202) gets 113's path, unchanged — delete_my_account_check as the
// caller, then GoTrue — so a shopper's deletion keeps working whatever
// order the database and this Worker go live in (review S6).
//
// Body: { confirmed_orgs: [uuid] — the businesses the confirmation
// showed, apple_authorization_code?: string, apple_client?: "app" |
// "web" }. Nothing in it names a
// person.
async function deleteMe(request, env) {
  const token = bearer(request);
  if (!token) return problem(401, "Sign in first.");
  if (!env.SUPABASE_SERVICE_ROLE_KEY) return problem(501, "Not configured.");

  let body = {};
  try {
    body = (await request.json()) || {};
  } catch {
    body = {};
  }

  const me = await whoAmI(env, token);
  if (!me) return problem(401, "Sign in first.");
  if (!signedInRecently(token)) {
    return problem(401, "Par sécurité, reconnectez-vous avant de supprimer votre compte : la connexion doit dater de moins de 10 minutes.", "reauth");
  }
  if (await isPlatformAdmin(env, me.id)) {
    return problem(403, "Ce compte ne peut pas être supprimé.");
  }

  const confirmed = Array.isArray(body.confirmed_orgs)
    ? body.confirmed_orgs.filter((id) => typeof id === "string" && UUID.test(id))
    : null;

  // 1. What will go, and what must be stopped first.
  const stopsAnswer = await rpcAsService(env, "delete_my_account_stops", { p_me: me.id, p_confirmed_orgs: confirmed });
  if (!stopsAnswer.ok) {
    // Only « no such function » (a database before 128) takes 113's path —
    // never any other 404 (SEC_AUDIT_2 L15).
    if (stopsAnswer.code === "PGRST202") return deleteMeBefore128(env, token, me);
    if (stopsAnswer.code === "P0001" && stopsAnswer.message) {
      return problem(409, stopsAnswer.message, stopsAnswer.details || "refused", stopsAnswer.hint || undefined);
    }
    return problem(502, "La vérification du compte a échoué.");
  }
  const stops = stopsAnswer.value || {};
  if (stops.user_id !== me.id) return problem(403, "Ce compte ne peut pas être supprimé.");
  const google = Array.isArray(stops.google) ? stops.google : [];
  const stripe = Array.isArray(stops.stripe) ? stops.stripe : [];

  // 2. Stripe and Google Play stopped — all of them, or nothing deleted.
  const stopped = { google: [], stripe: [] };
  const notStopped = (name) => problem(503,
    `Nous n'avons pas pu arrêter l'abonnement de « ${name} » : rien n'a été supprimé. Réessayez dans un moment ou écrivez à l'aide.`,
    "not_stopped", name);
  let failedOn = null;
  if (stripe.length && !env.STRIPE_SECRET_KEY) {
    console.error("account deletion refused: STRIPE_SECRET_KEY not set, a card subscription to cancel");
    failedOn = stripe[0].org || "";
  } else if (google.length && !env.PLAY_SERVICE_ACCOUNT_JSON) {
    console.error("account deletion refused: PLAY_SERVICE_ACCOUNT_JSON not set, a Google Play subscription to revoke");
    failedOn = google[0].org || "";
  }
  for (const sub of failedOn === null ? stripe : []) {
    try {
      const res = await fetch(`https://api.stripe.com/v1/subscriptions/${encodeURIComponent(sub.id)}`, {
        method: "DELETE",
        headers: { Authorization: `Bearer ${env.STRIPE_SECRET_KEY}` },
      });
      // 404: Stripe has no such subscription running — nothing bills.
      if (!res.ok && res.status !== 404) throw new Error(`Stripe answered ${res.status}`);
      stopped.stripe.push(sub.id);
    } catch (err) {
      console.error("account deletion: Stripe subscription not cancelled", sub.id, String(err?.message || err));
      failedOn = sub.org || "";
      break;
    }
  }
  for (const sub of failedOn === null ? google : []) {
    try {
      await googleRevoke(env, sub.token, { fetch: (...a) => fetch(...a) });
      stopped.google.push(sub.token);
    } catch (err) {
      // Google no longer knows the purchase (404/410): nothing bills.
      if (err?.status === 404) {
        stopped.google.push(sub.token);
        continue;
      }
      console.error("account deletion: Google Play subscription not revoked", sub.org, String(err?.code || err?.message || err));
      failedOn = sub.org || "";
      break;
    }
  }

  // 3. Written down before any purge — what was stopped, even if a later
  // step fails (and when this one fails, what was stopped is in the log).
  if (stopped.stripe.length || stopped.google.length) {
    // Stripe's ids (useless without Mara's key); of Google's purchase
    // tokens — bearer identifiers for the Play API — the count and the last
    // 6 characters only (SEC_AUDIT_2 L2).
    console.log("account deletion: stopped", JSON.stringify({
      user: me.id,
      stripe: stopped.stripe,
      google: stopped.google.length,
      google_ends: stopped.google.map((t) => `…${String(t).slice(-6)}`),
    }));
  }
  if (stopped.stripe.length || stopped.google.length || failedOn === null) {
    const noted = await rpcAsService(env, "account_deletion_note", {
      p_me: me.id, p_businesses: stops.businesses || [], p_stopped: stopped,
    });
    if (!noted.ok && failedOn === null) {
      console.error("account deletion: the note failed", noted.status, noted.code);
      return problem(502, "La suppression du compte a échoué.");
    }
  }
  if (failedOn !== null) return notStopped(failedOn);

  // 4. The deletion.
  const answer = await rpcAsService(env, "delete_my_account", {
    p_me: me.id, p_confirmed_orgs: confirmed, p_stopped: stopped,
  });
  if (!answer.ok) {
    if (answer.code === "P0001" && answer.message) {
      return problem(409, answer.message, answer.details || "refused", answer.hint || undefined);
    }
    return problem(502, "La vérification du compte a échoué.");
  }
  const done = answer.value || {};
  const userId = done.user_id;
  if (typeof userId !== "string" || !UUID.test(userId) || userId !== me.id) {
    return problem(403, "Ce compte ne peut pas être supprimé.");
  }

  // 5. Sign in with Apple.
  const notes = [];
  let appleSignin = null;
  if (signedInWithApple(me)) {
    appleSignin = false;
    try {
      appleSignin = await revokeAppleSignIn(env, body.apple_authorization_code, body.apple_client, fetch,
        appleWebRedirect(request, env));
    } catch (err) {
      console.error("account deletion: Sign in with Apple token not revoked", String(err?.message || err));
    }
    if (!appleSignin) notes.push("apple_signin");
  }

  // 6. GoTrue.
  const gone = await gotrueDelete(env, userId, done.mode === "soft" ? "soft" : "hard");
  if (!gone.ok) return gone.response;
  return json({
    ok: true,
    mode: gone.mode,
    businesses: Array.isArray(done.businesses) ? done.businesses : [],
    stopped: { google: stopped.google.length, stripe: stopped.stripe.length },
    apple_store_to_cancel: Number(done.apple_store || 0),
    apple_signin_revoked: appleSignin,
    not_done: notes,
  });
}

// The auth user, hard or soft; a hard delete GoTrue refuses retried soft.
async function gotrueDelete(env, userId, wanted) {
  let mode = wanted;
  let res = await admin(env, "DELETE", userId, mode === "soft" ? { should_soft_delete: true } : null);
  if (mode === "hard" && res.status >= 500) {
    // A key delete_my_account did not know of: the account kept as a
    // shell rather than not deleted.
    console.error("gotrue delete self, retried soft", res.status, await res.text());
    mode = "soft";
    res = await admin(env, "DELETE", userId, { should_soft_delete: true });
  }
  if (!res.ok && res.status !== 404) {
    console.error("gotrue delete self", res.status, await res.text());
    if (res.status >= 500) {
      return { ok: false, response: problem(409, "La suppression n'a pas pu se faire — écrivez à Mara.") };
    }
    return { ok: false, response: problem(502, "La suppression du compte a échoué.") };
  }
  return { ok: true, mode };
}

// 113's path, for a database still before 128: delete_my_account_check
// as the caller (a shopper with nothing on any business's books), then
// GoTrue. What the Worker deployed before 130 did, word for word.
async function deleteMeBefore128(env, token, me) {
  const answer = await rpcAsCaller(env, token, "delete_my_account_check", {});
  if (answer.status === 401) return problem(401, "Sign in first.");
  if (!answer.ok) {
    if (answer.code === "P0001" && answer.message) return problem(409, answer.message);
    return problem(502, "La vérification du compte a échoué.");
  }
  if (answer.value !== me.id) return problem(403, "Ce compte ne peut pas être supprimé.");
  const res = await admin(env, "DELETE", me.id, null);
  if (!res.ok && res.status !== 404) {
    console.error("gotrue delete self", res.status, await res.text());
    if (res.status >= 500) {
      return problem(409, "La suppression n'a pas pu se faire — écrivez à Mara.");
    }
    return problem(502, "La suppression du compte a échoué.");
  }
  return json({ ok: true, mode: "hard", businesses: [], stopped: { google: 0, stripe: 0 },
    apple_store_to_cancel: 0, apple_signin_revoked: null, not_done: [] });
}

// When the person last signed in, from their token (GoTrue has just
// vouched for it, whoAmI): the latest of the token's authentication
// methods (amr — kept as they were across refreshes, so a refreshed token
// is not a fresh sign-in), or its issue time when it carries none.
export function signedInRecently(token, now = Date.now()) {
  let claims;
  try {
    claims = JSON.parse(new TextDecoder().decode(base64url(token.split(".")[1] || "")));
  } catch {
    return false;
  }
  const amr = Array.isArray(claims?.amr) ? claims.amr : [];
  const times = amr.map((m) => Number(m?.timestamp)).filter((t) => Number.isFinite(t) && t > 0);
  const at = times.length ? Math.max(...times) : Number(claims?.auth_time || claims?.iat);
  if (!Number.isFinite(at) || at <= 0) return false;
  const age = now / 1000 - at;
  return age >= -60 && age <= FRESH_SIGN_IN_SECONDS;
}

function base64url(text) {
  const b64 = text.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((text.length + 3) % 4);
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

// The caller, as GoTrue knows them from their own token.
async function whoAmI(env, token) {
  const res = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: env.SUPABASE_PUBLISHABLE_KEY, Authorization: `Bearer ${token}` },
  });
  if (!res.ok) return null;
  const user = await res.json().catch(() => null);
  return user && typeof user.id === "string" && UUID.test(user.id) ? user : null;
}

function signedInWithApple(user) {
  const providers = user?.app_metadata?.providers;
  return (Array.isArray(providers) && providers.includes("apple"))
    || (Array.isArray(user?.identities) && user.identities.some((i) => i?.provider === "apple"));
}

// Sign in with Apple's REST API: the authorization code the app just got
// traded for a refresh token, which is then revoked. True when Apple said
// so; false when the key or the code is missing (logged by the caller).
//
// Whose code it is (139): [client] "web" — the website's popup, the
// Services ID's — or anything else, the iPhone's, bf.kaj.app's. That
// client id is tried first; when Apple refuses the code for it, the
// other. The revocation goes with the client id the code was traded for.
//
// A website code was issued for a return URL (the popup's
// `<origin>/connexion`), and Apple trades it only when that same
// redirect_uri comes with it: [redirectUri], sent with the Services ID
// only — the iPhone's codes have none.
export async function revokeAppleSignIn(env, code, client, fetchImpl = fetch, redirectUri = null) {
  if (!env.APPLE_SIGNIN_KEY_ID || !env.APPLE_SIGNIN_PRIVATE_KEY) {
    console.error("account deletion: no Sign in with Apple key (APPLE_SIGNIN_KEY_ID / APPLE_SIGNIN_PRIVATE_KEY)");
    return false;
  }
  if (typeof code !== "string" || !code) {
    console.error("account deletion: no Apple authorization code from the app");
    return false;
  }
  const appId = env.APPLE_SIGNIN_CLIENT_ID || "bf.kaj.app";
  const webId = env.APPLE_WEB_SERVICES_ID || "bf.kaj.app.web";
  const order = [...new Set(client === "web" ? [webId, appId] : [appId, webId])];
  const form = (fields) => ({
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(fields).toString(),
  });
  let lastStatus = 0;
  for (const clientId of order) {
    const secret = await appleClientSecret(env, clientId);
    const fields = { client_id: clientId, client_secret: secret, code, grant_type: "authorization_code" };
    if (clientId === webId && redirectUri) fields.redirect_uri = redirectUri;
    const tokenRes = await fetchImpl("https://appleid.apple.com/auth/token", form(fields));
    const tokens = await tokenRes.json().catch(() => ({}));
    const refresh = tokens.refresh_token || tokens.access_token;
    if (!tokenRes.ok || !refresh) {
      lastStatus = tokenRes.status;
      continue;
    }
    const revokeRes = await fetchImpl("https://appleid.apple.com/auth/revoke", form({
      client_id: clientId,
      client_secret: secret,
      token: refresh,
      token_type_hint: tokens.refresh_token ? "refresh_token" : "access_token",
    }));
    if (!revokeRes.ok) throw new Error(`Apple revoke answered ${revokeRes.status}`);
    return true;
  }
  throw new Error(`Apple token answered ${lastStatus}`);
}

// The website's Apple return URL (139): the page that opened Apple's
// popup is `<origin>/connexion`, a return URL of the Services ID; the
// origin is the request's own, and only one of ALLOWED_ORIGINS. Null
// otherwise (the iPhone app sends no Origin).
function appleWebRedirect(request, env) {
  const origin = request.headers.get("Origin");
  const allowed = (env.ALLOWED_ORIGINS || "").split(",").map((o) => o.trim()).filter(Boolean);
  return origin && allowed.includes(origin) ? `${origin}/connexion` : null;
}

// A five-minute client secret for [clientId], signed with the Sign in
// with Apple key.
function appleClientSecret(env, clientId) {
  const iat = Math.floor(Date.now() / 1000);
  return signEs256({ kid: env.APPLE_SIGNIN_KEY_ID }, {
    iss: env.APPLE_TEAM_ID || "9K236BL7SX",
    iat,
    exp: iat + 300,
    aud: "https://appleid.apple.com",
    sub: clientId,
  }, env.APPLE_SIGNIN_PRIVATE_KEY);
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

// Whether the target is one of the platform's admins. Fails closed: an
// answer that cannot be read counts as yes, so nothing is reset on a doubt.
async function isPlatformAdmin(env, userId) {
  const res = await fetch(
    `${env.SUPABASE_URL}/rest/v1/profiles?id=eq.${encodeURIComponent(userId)}&select=is_platform_admin`,
    {
      headers: {
        apikey: env.SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
        Accept: "application/json",
      },
    },
  );
  if (!res.ok) return true;
  const rows = await res.json();
  return !Array.isArray(rows) || rows.some((r) => r && r.is_platform_admin === true);
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

// A function's answer, asked as the caller: its value, or PostgREST's
// status and the database's code and words when it refused.
async function rpcAsCaller(env, token, fn, params, apikey = env.SUPABASE_PUBLISHABLE_KEY) {
  const res = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: {
      apikey,
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    body: JSON.stringify(params),
  });
  let body = null;
  try {
    body = await res.json();
  } catch {
    body = null;
  }
  if (res.ok) return { ok: true, status: res.status, value: body };
  return {
    ok: false,
    status: res.status,
    code: body && typeof body.code === "string" ? body.code : null,
    message: body && typeof body.message === "string" ? body.message : null,
    // The database's code for its refusal (raise … using detail) and the
    // business it names (hint), for the app to say in its language.
    details: body && typeof body.details === "string" && body.details ? body.details : null,
    hint: body && typeof body.hint === "string" && body.hint ? body.hint : null,
  };
}

// The account deletion's own functions (128 section 8), the service
// role's alone: called with the key, for the id GoTrue gave (whoAmI).
async function rpcAsService(env, fn, params) {
  return rpcAsCaller(env, env.SUPABASE_SERVICE_ROLE_KEY, fn, params, env.SUPABASE_SERVICE_ROLE_KEY);
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

// [code] says why, for the app to say it in the reader's language (130);
// [name], the business it names.
function problem(status, detail, code, name) {
  const generic = code ? null : FRENCH[status];
  return json({ error: generic || detail, detail, status, code: code || undefined, name: name || undefined }, status);
}
