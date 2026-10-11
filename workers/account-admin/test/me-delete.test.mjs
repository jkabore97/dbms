// Plays PostgREST, GoTrue, Google Play, Stripe and Apple against
// workers/account-admin's « Supprimer mon compte » (113, for real since
// 130) — no network.
//
//   node --test workers/account-admin/test
//
// The rule the Worker keeps: Postgres decides and does (128's section 8,
// the service role's alone since review B1, for the id GoTrue gave); the
// Worker first stops what Mara bills outside for a business that will go
// — every Stripe subscription, every Google Play purchase — and deletes
// nothing when one cannot be stopped; a deletion needs a sign-in less
// than ten minutes old (S8). A fake fetch answers every place the Worker
// talks to and records each call.

import assert from "node:assert/strict";
import { generateKeyPairSync } from "node:crypto";
import { test } from "node:test";

import worker, { signedInRecently } from "../src/index.js";

const ME = "11311311-0000-0000-0000-000000000005";
const SHOP = "12800000-0000-0000-0000-000000000011";
const appleKey = generateKeyPairSync("ec", { namedCurve: "P-256" }).privateKey.export({ type: "pkcs8", format: "pem" });
const playKey = generateKeyPairSync("rsa", { modulusLength: 2048 }).privateKey.export({ type: "pkcs8", format: "pem" });
const env = {
  SUPABASE_URL: "https://db.example",
  SUPABASE_PUBLISHABLE_KEY: "anon-key",
  SUPABASE_SERVICE_ROLE_KEY: "service-key",
  ALLOWED_ORIGINS: "https://marakaj.com",
};
const full = {
  ...env,
  PLAY_SERVICE_ACCOUNT_JSON: JSON.stringify({
    client_email: "mara@play.example", private_key: playKey, token_uri: "https://oauth2.example/token",
  }),
  STRIPE_SECRET_KEY: "sk_test_kaj",
  APPLE_SIGNIN_KEY_ID: "SIWA123",
  APPLE_SIGNIN_PRIVATE_KEY: appleKey,
};

/// A Supabase-shaped access token: signed in [age] seconds ago (amr), the
/// token itself issued [iatAge] seconds ago. Only its claims matter here:
/// GoTrue (/auth/v1/user) is what vouches for it.
function jwt({ age = 30, iatAge = age, amr = true } = {}) {
  const now = Math.floor(Date.now() / 1000);
  const part = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
  const claims = { sub: ME, role: "authenticated", iat: now - iatAge, exp: now + 3600 };
  if (amr) claims.amr = [{ method: "password", timestamp: now - age }];
  return `${part({ alg: "HS256", typ: "JWT" })}.${part(claims)}.c2ln`;
}
const FRESH = jwt();

/// A fake world. [stops] is what delete_my_account_stops answers (or
/// [refused] its refusal); [answer] what delete_my_account answers.
function world({ stops = plainStops, refused = null, answer, admin = false, gotrue = [200], providers = ["email"],
  user = ME, stripe = 200, google = 200, before128 = false, check = { ok: true, value: ME } } = {}) {
  const calls = [];
  const statuses = [...gotrue];
  const fetch = async (url, init = {}) => {
    const u = new URL(url);
    const auth = (init.headers || {}).Authorization;
    const body = typeof init.body === "string" ? init.body : null;
    calls.push({ host: u.host, path: u.pathname, method: init.method || "GET", auth, body });
    const person = typeof auth === "string" && auth.startsWith("Bearer ey") ;
    if (u.host === "db.example" && u.pathname === "/auth/v1/user") {
      if (!person) return new Response("{}", { status: 401 });
      return Response.json({ id: user, app_metadata: { providers }, identities: providers.map((p) => ({ provider: p })) });
    }
    if (u.pathname.startsWith("/rest/v1/rpc/")) {
      const fn = u.pathname.slice("/rest/v1/rpc/".length);
      if (fn === "delete_my_account_check") {
        if (!person) return new Response(JSON.stringify({ code: "PGRST301", message: "JWT expired" }), { status: 401 });
        return check.ok ? Response.json(check.value)
          : new Response(JSON.stringify({ code: "P0001", message: check.refused }), { status: 400 });
      }
      // Section 8 is the service role's.
      assert.equal(auth, "Bearer service-key", `${fn} called without the key`);
      if (before128) {
        return new Response(JSON.stringify({ code: "PGRST202", message: `Could not find the function public.${fn}` }), { status: 404 });
      }
      if (fn === "delete_my_account_stops") {
        if (refused) return new Response(JSON.stringify({ code: "P0001", message: refused.message, details: refused.code, hint: refused.name || "" }), { status: 400 });
        return Response.json(stops);
      }
      if (fn === "account_deletion_note") return new Response(null, { status: 204 });
      if (fn === "delete_my_account") {
        const sent = JSON.parse(body);
        const left = (stops.google || []).find((g) => !(sent.p_stopped.google || []).includes(g.token))
          || (stops.stripe || []).find((t) => !(sent.p_stopped.stripe || []).includes(t.id));
        if (left) {
          return new Response(JSON.stringify({ code: "P0001", message: `Nous n'avons pas pu arrêter l'abonnement de « ${left.org} »`, details: "not_stopped" }), { status: 400 });
        }
        return Response.json(answer ?? { user_id: user, mode: "hard", businesses: stops.businesses || [],
          google: stops.google || [], stripe: stops.stripe || [], apple_store: stops.apple_store || 0 });
      }
      throw new Error(`unexpected rpc ${fn}`);
    }
    if (u.pathname === "/rest/v1/profiles") {
      assert.equal(auth, "Bearer service-key");
      return Response.json([{ is_platform_admin: admin }]);
    }
    if (u.pathname.startsWith("/auth/v1/admin/users/")) {
      assert.equal(auth, "Bearer service-key");
      return new Response("{}", { status: statuses.shift() ?? 200 });
    }
    if (url === "https://oauth2.example/token") return Response.json({ access_token: "ya29" });
    if (u.host === "androidpublisher.googleapis.com") return new Response("{}", { status: google });
    if (u.host === "api.stripe.com") return new Response(JSON.stringify({ id: "sub_fin", status: "canceled" }), { status: stripe });
    if (url === "https://appleid.apple.com/auth/token") return Response.json({ refresh_token: "r-apple" });
    if (url === "https://appleid.apple.com/auth/revoke") return new Response(null, { status: 200 });
    throw new Error(`unexpected call ${url}`);
  };
  return { calls, fetch };
}

async function deleteMe(fake, { token = FRESH, body = {}, e = env } = {}) {
  const saved = globalThis.fetch;
  const savedLog = [console.log, console.error];
  const logged = [];
  globalThis.fetch = fake.fetch;
  console.log = (...a) => logged.push(a.join(" "));
  console.error = (...a) => logged.push(a.join(" "));
  try {
    const res = await worker.fetch(new Request("https://kaj-account.example/v1/me/delete", {
      method: "POST",
      headers: {
        Origin: "https://marakaj.com",
        "Content-Type": "application/json",
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: typeof body === "string" ? body : JSON.stringify(body),
    }), e);
    return { status: res.status, body: await res.json(), cors: res.headers.get("Access-Control-Allow-Origin"), logged };
  } finally {
    globalThis.fetch = saved;
    [console.log, console.error] = savedLog;
  }
}

const plainStops = { user_id: ME, orgs: [], businesses: [], google: [], stripe: [], apple_store: 0 };
const ownerStops = {
  user_id: ME, orgs: [SHOP], businesses: ["Boutique Fin", "Ferme Fin"],
  google: [{ token: "fin-google-token", org_id: SHOP, org: "Boutique Fin" }],
  stripe: [{ id: "sub_fin", org_id: SHOP, org: "Ferme Fin" }], apple_store: 1,
};
const deleted = (fake) => fake.calls.some((c) => c.path === "/rest/v1/rpc/delete_my_account")
  || fake.calls.some((c) => c.method === "DELETE" && c.path.startsWith("/auth/v1/admin/users/"));
const rpcs = (fake) => fake.calls.filter((c) => c.path.startsWith("/rest/v1/rpc/")).map((c) => c.path.slice(13));

test("a shopper: GoTrue's id, and only it, deleted outright — by the Worker, with the key", async () => {
  const fake = world();
  // Whatever the request body names, no person is read from it.
  const out = await deleteMe(fake, { body: { user_id: "someone-else" } });
  assert.equal(out.status, 200, JSON.stringify(out.body));
  assert.equal(out.body.ok, true);
  assert.equal(out.body.mode, "hard");
  assert.equal(out.cors, "https://marakaj.com");
  const del = fake.calls.filter((c) => c.method === "DELETE");
  assert.equal(del.length, 1);
  assert.equal(del[0].path, `/auth/v1/admin/users/${ME}`);
  assert.equal(del[0].body, null, "a hard delete has no body");
  // Who first, the platform lock next, then the database, with the key.
  assert.deepEqual(fake.calls.slice(0, 3).map((c) => c.path),
    ["/auth/v1/user", "/rest/v1/profiles", "/rest/v1/rpc/delete_my_account_stops"]);
  assert.deepEqual(JSON.parse(fake.calls[2].body), { p_me: ME, p_confirmed_orgs: null });
  assert.deepEqual(rpcs(fake), ["delete_my_account_stops", "account_deletion_note", "delete_my_account"]);
});

test("B1 an owner: Stripe cancelled and Google revoked BEFORE the database deletes; the ids logged first", async () => {
  const fake = world({ stops: ownerStops });
  const out = await deleteMe(fake, { e: full, body: { confirmed_orgs: [SHOP, "not-an-id"] } });
  assert.equal(out.status, 200, JSON.stringify(out.body));
  assert.deepEqual(JSON.parse(fake.calls.find((c) => c.path.endsWith("/delete_my_account_stops")).body),
    { p_me: ME, p_confirmed_orgs: [SHOP] });
  assert.deepEqual(out.body.stopped, { google: 1, stripe: 1 });
  assert.equal(out.body.apple_store_to_cancel, 1);
  assert.deepEqual(out.body.not_done, []);
  const at = (pred) => fake.calls.findIndex(pred);
  const stripe = at((c) => c.host === "api.stripe.com");
  const revoke = at((c) => c.host === "androidpublisher.googleapis.com");
  const note = at((c) => c.path.endsWith("/account_deletion_note"));
  const purge = at((c) => c.path === "/rest/v1/rpc/delete_my_account");
  const gotrue = at((c) => c.method === "DELETE" && c.path.startsWith("/auth/v1/admin/users/"));
  assert.ok(stripe > 0 && revoke > 0 && stripe < note && revoke < note && note < purge && purge < gotrue,
    `order: stripe ${stripe}, google ${revoke}, note ${note}, purge ${purge}, gotrue ${gotrue}`);
  assert.equal(fake.calls[stripe].method, "DELETE");
  assert.equal(fake.calls[stripe].path, "/v1/subscriptions/sub_fin");
  assert.equal(fake.calls[revoke].path, "/androidpublisher/v3/applications/bf.kaj.app/purchases/subscriptionsv2/tokens/fin-google-token:revoke");
  assert.deepEqual(JSON.parse(fake.calls[note].body).p_stopped, { google: ["fin-google-token"], stripe: ["sub_fin"] });
  assert.deepEqual(JSON.parse(fake.calls[purge].body).p_stopped, { google: ["fin-google-token"], stripe: ["sub_fin"] });
  assert.ok(out.logged.some((l) => l.includes("account deletion: stopped") && l.includes("sub_fin")));
});

test("B1 Stripe fails: nothing deleted, said in French; what was stopped before it is logged", async () => {
  for (const status of [500, 402, 429]) {
    const fake = world({ stops: ownerStops, stripe: status });
    const out = await deleteMe(fake, { e: full, body: { confirmed_orgs: [SHOP] } });
    assert.equal(out.status, 503, `Stripe ${status}`);
    assert.equal(out.body.code, "not_stopped");
    assert.equal(out.body.name, "Ferme Fin");
    assert.equal(out.body.error, "Nous n'avons pas pu arrêter l'abonnement de « Ferme Fin » : rien n'a été supprimé. Réessayez dans un moment ou écrivez à l'aide.");
    assert.equal(deleted(fake), false, "nothing deleted");
    assert.equal(fake.calls.some((c) => c.host === "androidpublisher.googleapis.com"), false, "stopped at the first failure");
  }
  // Google fails after Stripe was cancelled: refused, and Stripe's id is
  // in the log (the note, before nothing is purged).
  const fake = world({ stops: ownerStops, google: 500 });
  const out = await deleteMe(fake, { e: full, body: { confirmed_orgs: [SHOP] } });
  assert.equal(out.status, 503);
  assert.equal(out.body.name, "Boutique Fin");
  assert.equal(deleted(fake), false);
  const note = fake.calls.find((c) => c.path.endsWith("/account_deletion_note"));
  assert.deepEqual(JSON.parse(note.body).p_stopped, { google: [], stripe: ["sub_fin"] });
});

test("B1 a key missing while there is something to stop: refused, nothing deleted, nothing asked outside", async () => {
  for (const missing of ["STRIPE_SECRET_KEY", "PLAY_SERVICE_ACCOUNT_JSON"]) {
    const { [missing]: _, ...e } = full;
    const fake = world({ stops: ownerStops });
    const out = await deleteMe(fake, { e, body: { confirmed_orgs: [SHOP] } });
    assert.equal(out.status, 503, missing);
    assert.equal(out.body.code, "not_stopped");
    assert.match(out.body.error, /^Nous n'avons pas pu arrêter l'abonnement de « .* » : rien n'a été supprimé\. Réessayez dans un moment ou écrivez à l'aide\.$/);
    assert.equal(deleted(fake), false);
    assert.equal(fake.calls.some((c) => c.host === "api.stripe.com" || c.host === "androidpublisher.googleapis.com"), false);
    assert.ok(out.logged.some((l) => l.includes(`${missing} not set`)), out.logged.join("\n"));
  }
});

test("B1 nothing to cancel: deleted, with no key at all", async () => {
  const fake = world({ stops: { ...ownerStops, google: [], stripe: [], apple_store: 0 } });
  const out = await deleteMe(fake, { body: { confirmed_orgs: [SHOP] } });
  assert.equal(out.status, 200, JSON.stringify(out.body));
  assert.deepEqual(out.body.stopped, { google: 0, stripe: 0 });
  assert.equal(fake.calls.some((c) => c.path === "/rest/v1/rpc/delete_my_account"), true);
  assert.equal(fake.calls.filter((c) => c.method === "DELETE").length, 1);
  // Already gone at Stripe or Google (404): nothing bills, so it goes on.
  const gone = world({ stops: ownerStops, stripe: 404, google: 404 });
  const out2 = await deleteMe(gone, { e: full, body: { confirmed_orgs: [SHOP] } });
  assert.equal(out2.status, 200, JSON.stringify(out2.body));
});

test("S8 a sign-in older than ten minutes: 401 « reauth », nothing asked of the database", async () => {
  for (const token of [jwt({ age: 11 * 60 }), jwt({ age: 3600, iatAge: 5 }), "not-a-jwt"]) {
    const fake = world({ stops: ownerStops });
    const out = await deleteMe(fake, { token: token === "not-a-jwt" ? token : token, e: full, body: { confirmed_orgs: [SHOP] } });
    assert.equal(out.status, 401);
    if (token !== "not-a-jwt") {
      assert.equal(out.body.code, "reauth");
      assert.equal(out.body.error, "Par sécurité, reconnectez-vous avant de supprimer votre compte : la connexion doit dater de moins de 10 minutes.");
    }
    assert.equal(fake.calls.some((c) => c.path.includes("/rpc/") || c.host !== "db.example"), false);
    assert.equal(deleted(fake), false);
  }
  // A refreshed token keeps its sign-in time (amr): a fresh iat is not enough.
  assert.equal(signedInRecently(jwt({ age: 3600, iatAge: 5 })), false);
  // No amr: the token's own issue time.
  assert.equal(signedInRecently(jwt({ amr: false, iatAge: 60 })), true);
  assert.equal(signedInRecently(jwt({ amr: false, iatAge: 900 })), false);
  assert.equal(signedInRecently(jwt({ age: 9 * 60 })), true);
});

test("a member whose name is on a business's books: soft-deleted; a hard delete refused is retried soft", async () => {
  const soft = world({ answer: { ...plainStops, user_id: ME, mode: "soft" } });
  let out = await deleteMe(soft);
  assert.equal(out.status, 200);
  assert.equal(out.body.mode, "soft");
  const del = soft.calls.filter((c) => c.method === "DELETE");
  assert.deepEqual(JSON.parse(del[0].body), { should_soft_delete: true });

  const retried = world({ gotrue: [500, 200] });
  out = await deleteMe(retried);
  assert.equal(out.status, 200);
  assert.equal(out.body.mode, "soft");
  const dels = retried.calls.filter((c) => c.method === "DELETE");
  assert.equal(dels.length, 2);
  assert.equal(dels[0].body, null);
  assert.deepEqual(JSON.parse(dels[1].body), { should_soft_delete: true });
});

test("Sign in with Apple: the fresh code traded and the token revoked; no key or no code, logged and done", async () => {
  const fake = world({ providers: ["apple"] });
  let out = await deleteMe(fake, { e: full, body: { apple_authorization_code: "c-apple" } });
  assert.equal(out.status, 200);
  assert.equal(out.body.apple_signin_revoked, true);
  const tokenCall = fake.calls.find((c) => c.path === "/auth/token");
  const form = new URLSearchParams(tokenCall.body);
  assert.equal(form.get("client_id"), "bf.kaj.app");
  assert.equal(form.get("grant_type"), "authorization_code");
  assert.equal(form.get("code"), "c-apple");
  const [head, claims] = form.get("client_secret").split(".").slice(0, 2)
    .map((p) => JSON.parse(Buffer.from(p, "base64url").toString()));
  assert.deepEqual(head, { alg: "ES256", kid: "SIWA123" });
  assert.equal(claims.iss, "9K236BL7SX");
  assert.equal(claims.sub, "bf.kaj.app");
  assert.equal(claims.aud, "https://appleid.apple.com");
  const revoke = new URLSearchParams(fake.calls.find((c) => c.path === "/auth/revoke").body);
  assert.equal(revoke.get("token"), "r-apple");
  assert.equal(revoke.get("token_type_hint"), "refresh_token");

  const noKey = world({ providers: ["apple"] });
  out = await deleteMe(noKey, { body: { apple_authorization_code: "c-apple" } });
  assert.equal(out.status, 200);
  assert.equal(out.body.apple_signin_revoked, false);
  assert.deepEqual(out.body.not_done, ["apple_signin"]);
  assert.equal(noKey.calls.some((c) => c.host === "appleid.apple.com"), false);
  assert.equal(noKey.calls.filter((c) => c.method === "DELETE").length, 1, "the account is deleted all the same");

  const noCode = world({ providers: ["apple"] });
  out = await deleteMe(noCode, { e: full });
  assert.equal(out.body.apple_signin_revoked, false);

  // Not an Apple account: nothing asked of Apple.
  const google = world({ providers: ["google"] });
  out = await deleteMe(google, { e: full, body: { apple_authorization_code: "c" } });
  assert.equal(out.body.apple_signin_revoked, null);
  assert.equal(google.calls.some((c) => c.host === "appleid.apple.com"), false);
});

test("the database's refusal is said in its words with its code, and nothing is deleted or stopped", async () => {
  const message = "Une commande de « Boutique Fin » est en route ou déjà payée en ligne : livrez-la ou remboursez-la, puis supprimez votre compte.";
  const fake = world({ stops: ownerStops, refused: { message, code: "business_order", name: "Boutique Fin" } });
  const out = await deleteMe(fake, { e: full });
  assert.equal(out.status, 409);
  assert.equal(out.body.error, message);
  assert.equal(out.body.code, "business_order");
  assert.equal(out.body.name, "Boutique Fin");
  assert.equal(deleted(fake), false);
  assert.equal(fake.calls.some((c) => c.host !== "db.example"), false);
  // S5: a Wave payout Mara still owes the business, likewise.
  const owed = world({ refused: { message: "Mara doit encore verser à « Boutique Fin » …", code: "payout", name: "Boutique Fin" } });
  const out2 = await deleteMe(owed, { e: full });
  assert.equal(out2.status, 409);
  assert.equal(out2.body.code, "payout");
  assert.equal(deleted(owed), false);
});

test("S6 a database still at 127: 113's path, unchanged — the check as the caller, then GoTrue", async () => {
  const fake = world({ before128: true });
  const out = await deleteMe(fake);
  assert.equal(out.status, 200, JSON.stringify(out.body));
  assert.deepEqual(rpcs(fake), ["delete_my_account_stops", "delete_my_account_check"]);
  const check = fake.calls.find((c) => c.path.endsWith("/delete_my_account_check"));
  assert.ok(check.auth.startsWith("Bearer ey"), "113's check is the caller's");
  assert.equal(fake.calls.filter((c) => c.method === "DELETE").length, 1);
  // Its refusal (a member, on 127) is said as before.
  const member = world({ before128: true, check: { ok: false, refused: "Votre compte tient les livres d'une activité : écrivez à Mara." } });
  const out2 = await deleteMe(member);
  assert.equal(out2.status, 409);
  assert.equal(member.calls.some((c) => c.method === "DELETE"), false);
});

test("no token, an expired token, or no key: nothing is asked of the database or GoTrue", async () => {
  const none = world();
  assert.equal((await deleteMe(none, { token: null })).status, 401);
  assert.equal(none.calls.length, 0);

  const expired = world();
  const out = await deleteMe(expired, { token: "old-token" });
  assert.equal(out.status, 401);
  assert.equal(expired.calls.some((c) => c.path.includes("/rpc/")), false);
  assert.equal(expired.calls.some((c) => c.method === "DELETE"), false);

  const dormant = world();
  const { SUPABASE_SERVICE_ROLE_KEY: _, ...noKey } = env;
  assert.equal((await deleteMe(dormant, { e: noKey })).status, 501);
  assert.equal(dormant.calls.length, 0);
});

test("a platform account: refused before the database is asked to do anything", async () => {
  const fake = world({ admin: true });
  const out = await deleteMe(fake);
  assert.equal(out.status, 403);
  assert.equal(fake.calls.some((c) => c.path.includes("/rpc/")), false);
  assert.equal(fake.calls.some((c) => c.method === "DELETE"), false);
});

test("an answer for another id deletes nothing; GoTrue's failures are said", async () => {
  const odd = world({ stops: { ...plainStops, user_id: "11311311-0000-0000-0000-000000000099" } });
  assert.equal((await deleteMe(odd)).status, 403);
  assert.equal(deleted(odd), false);
  const odd2 = world({ answer: { ...plainStops, user_id: "11311311-0000-0000-0000-000000000099", mode: "hard" } });
  assert.equal((await deleteMe(odd2)).status, 403);
  assert.equal(odd2.calls.some((c) => c.method === "DELETE"), false);

  const gone = world({ gotrue: [404] });
  assert.equal((await deleteMe(gone)).status, 200);

  // GoTrue refusing even the soft delete: said as a 409 the person can
  // act on, never « réessayez ».
  const broken = world({ gotrue: [500, 500] });
  const out = await deleteMe(broken);
  assert.equal(out.status, 409);
  assert.equal(out.body.error, "La suppression n'a pas pu se faire — écrivez à Mara.");

  const refused = world({ gotrue: [403] });
  const other = await deleteMe(refused);
  assert.equal(other.status, 502);
  assert.equal(other.body.error, "L'opération a échoué. Réessayez.");
});
