// Plays PostgREST, GoTrue, Google Play, Stripe and Apple against
// workers/account-admin's « Supprimer mon compte » (113, for real since
// 130) — no network.
//
//   node --test workers/account-admin/test
//
// The rule the Worker keeps: Postgres decides and does, as the caller
// (128's delete_my_account); the service-role key only performs what is
// left — the auth user's deletion, hard or soft — and the Worker stops
// what Mara pays outside for a business that is gone. A fake fetch
// answers every place the Worker talks to and records each call.

import assert from "node:assert/strict";
import { generateKeyPairSync } from "node:crypto";
import { test } from "node:test";

import worker from "../src/index.js";

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

/// A fake world. [answer] is what delete_my_account answers (or refuses).
function world({ answer, admin = false, gotrue = [200], providers = ["email"], user = ME } = {}) {
  const calls = [];
  const statuses = [...gotrue];
  const fetch = async (url, init = {}) => {
    const u = new URL(url);
    const auth = (init.headers || {}).Authorization;
    const body = typeof init.body === "string" ? init.body : null;
    calls.push({ host: u.host, path: u.pathname, method: init.method || "GET", auth, body });
    if (u.host === "db.example" && u.pathname === "/auth/v1/user") {
      if (auth !== "Bearer person-token") return new Response("{}", { status: 401 });
      return Response.json({ id: user, app_metadata: { providers }, identities: providers.map((p) => ({ provider: p })) });
    }
    if (u.pathname === "/rest/v1/rpc/delete_my_account") {
      if (auth !== "Bearer person-token") {
        return new Response(JSON.stringify({ code: "PGRST301", message: "JWT expired" }), { status: 401 });
      }
      return answer.ok
        ? Response.json(answer.value)
        : new Response(JSON.stringify({ code: "P0001", message: answer.refused }), { status: 400 });
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
    if (u.host === "androidpublisher.googleapis.com") return Response.json({});
    if (u.host === "api.stripe.com") return Response.json({ id: "sub_fin", status: "canceled" });
    if (url === "https://appleid.apple.com/auth/token") return Response.json({ refresh_token: "r-apple" });
    if (url === "https://appleid.apple.com/auth/revoke") return new Response(null, { status: 200 });
    throw new Error(`unexpected call ${url}`);
  };
  return { calls, fetch };
}

async function deleteMe(fake, { token = "person-token", body = {}, e = env } = {}) {
  const saved = globalThis.fetch;
  globalThis.fetch = fake.fetch;
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
    return { status: res.status, body: await res.json(), cors: res.headers.get("Access-Control-Allow-Origin") };
  } finally {
    globalThis.fetch = saved;
  }
}

const plain = { user_id: ME, mode: "hard", businesses: [], google: [], stripe: [], apple_store: 0 };

test("a shopper: the database's own id, and only it, deleted outright", async () => {
  const fake = world({ answer: { ok: true, value: plain } });
  // Whatever the request body names, no person is read from it.
  const out = await deleteMe(fake, { body: { user_id: "someone-else" } });
  assert.equal(out.status, 200);
  assert.equal(out.body.ok, true);
  assert.equal(out.body.mode, "hard");
  assert.equal(out.cors, "https://marakaj.com");
  const del = fake.calls.filter((c) => c.method === "DELETE");
  assert.equal(del.length, 1);
  assert.equal(del[0].path, `/auth/v1/admin/users/${ME}`);
  assert.equal(del[0].body, null, "a hard delete has no body");
  // Who first, the platform lock next, then the database as the caller.
  assert.deepEqual(fake.calls.slice(0, 3).map((c) => c.path),
    ["/auth/v1/user", "/rest/v1/profiles", "/rest/v1/rpc/delete_my_account"]);
  assert.equal(fake.calls[2].auth, "Bearer person-token");
  assert.deepEqual(JSON.parse(fake.calls[2].body), { p_confirmed_orgs: null });
});

test("an owner: the businesses shown are sent; Google revoked, Stripe cancelled, the App Store counted", async () => {
  const fake = world({ answer: { ok: true, value: {
    user_id: ME, mode: "hard", businesses: ["Boutique Fin"],
    google: [{ token: "fin-google-token", org: "Boutique Fin" }], stripe: ["sub_fin"], apple_store: 1,
  } } });
  const out = await deleteMe(fake, { e: full, body: { confirmed_orgs: [SHOP, "not-an-id"] } });
  assert.equal(out.status, 200, JSON.stringify(out.body));
  assert.deepEqual(JSON.parse(fake.calls.find((c) => c.path.endsWith("/delete_my_account")).body),
    { p_confirmed_orgs: [SHOP] });
  assert.deepEqual(out.body.stopped, { google: 1, stripe: 1 });
  assert.equal(out.body.apple_store_to_cancel, 1);
  assert.deepEqual(out.body.not_done, []);
  const revoke = fake.calls.find((c) => c.host === "androidpublisher.googleapis.com");
  assert.equal(revoke.path, "/androidpublisher/v3/applications/bf.kaj.app/purchases/subscriptionsv2/tokens/fin-google-token:revoke");
  assert.deepEqual(JSON.parse(revoke.body), { revocationContext: { proratedRefund: {} } });
  const stripe = fake.calls.find((c) => c.host === "api.stripe.com");
  assert.equal(stripe.method, "DELETE");
  assert.equal(stripe.path, "/v1/subscriptions/sub_fin");
  // The outside first, the auth user last.
  assert.equal(fake.calls.at(-1).method, "DELETE");
});

test("without the Play or Stripe key, the rest is done and what was not is said", async () => {
  const fake = world({ answer: { ok: true, value: {
    ...plain, google: [{ token: "t", org: "Boutique Fin" }], stripe: ["sub_fin"],
  } } });
  const out = await deleteMe(fake);
  assert.equal(out.status, 200);
  assert.deepEqual(out.body.stopped, { google: 0, stripe: 0 });
  assert.deepEqual(out.body.not_done, ["google", "stripe"]);
  assert.equal(fake.calls.filter((c) => c.method === "DELETE").length, 1);
});

test("a member whose name is on a business's books: soft-deleted; a hard delete refused is retried soft", async () => {
  const soft = world({ answer: { ok: true, value: { ...plain, mode: "soft" } } });
  let out = await deleteMe(soft);
  assert.equal(out.status, 200);
  assert.equal(out.body.mode, "soft");
  const del = soft.calls.filter((c) => c.method === "DELETE");
  assert.deepEqual(JSON.parse(del[0].body), { should_soft_delete: true });

  const retried = world({ answer: { ok: true, value: plain }, gotrue: [500, 200] });
  out = await deleteMe(retried);
  assert.equal(out.status, 200);
  assert.equal(out.body.mode, "soft");
  const dels = retried.calls.filter((c) => c.method === "DELETE");
  assert.equal(dels.length, 2);
  assert.equal(dels[0].body, null);
  assert.deepEqual(JSON.parse(dels[1].body), { should_soft_delete: true });
});

test("Sign in with Apple: the fresh code traded and the token revoked; no key or no code, logged and done", async () => {
  const fake = world({ answer: { ok: true, value: plain }, providers: ["apple"] });
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

  const noKey = world({ answer: { ok: true, value: plain }, providers: ["apple"] });
  out = await deleteMe(noKey, { body: { apple_authorization_code: "c-apple" } });
  assert.equal(out.status, 200);
  assert.equal(out.body.apple_signin_revoked, false);
  assert.deepEqual(out.body.not_done, ["apple_signin"]);
  assert.equal(noKey.calls.some((c) => c.host === "appleid.apple.com"), false);
  assert.equal(noKey.calls.filter((c) => c.method === "DELETE").length, 1, "the account is deleted all the same");

  const noCode = world({ answer: { ok: true, value: plain }, providers: ["apple"] });
  out = await deleteMe(noCode, { e: full });
  assert.equal(out.body.apple_signin_revoked, false);

  // Not an Apple account: nothing asked of Apple.
  const google = world({ answer: { ok: true, value: plain }, providers: ["google"] });
  out = await deleteMe(google, { e: full, body: { apple_authorization_code: "c" } });
  assert.equal(out.body.apple_signin_revoked, null);
  assert.equal(google.calls.some((c) => c.host === "appleid.apple.com"), false);
});

test("the database's refusal is said in its words, and nothing is deleted or stopped", async () => {
  const refused = "Une commande de « Boutique Fin » est en route ou déjà payée en ligne : livrez-la ou remboursez-la, puis supprimez votre compte.";
  const fake = world({ answer: { ok: false, refused } });
  const out = await deleteMe(fake, { e: full });
  assert.equal(out.status, 409);
  assert.equal(out.body.error, refused);
  assert.equal(fake.calls.some((c) => c.method === "DELETE"), false);
  assert.equal(fake.calls.some((c) => c.host !== "db.example"), false);
});

test("no token, an expired token, or no key: nothing is asked of the database or GoTrue", async () => {
  const none = world({ answer: { ok: true, value: plain } });
  assert.equal((await deleteMe(none, { token: null })).status, 401);
  assert.equal(none.calls.length, 0);

  const expired = world({ answer: { ok: true, value: plain } });
  const out = await deleteMe(expired, { token: "old-token" });
  assert.equal(out.status, 401);
  assert.equal(expired.calls.some((c) => c.path.includes("/rpc/")), false);
  assert.equal(expired.calls.some((c) => c.method === "DELETE"), false);

  const dormant = world({ answer: { ok: true, value: plain } });
  const { SUPABASE_SERVICE_ROLE_KEY: _, ...noKey } = env;
  assert.equal((await deleteMe(dormant, { e: noKey })).status, 501);
  assert.equal(dormant.calls.length, 0);
});

test("a platform account: refused before the database is asked to do anything", async () => {
  const fake = world({ answer: { ok: true, value: plain }, admin: true });
  const out = await deleteMe(fake);
  assert.equal(out.status, 403);
  assert.equal(fake.calls.some((c) => c.path.includes("/rpc/")), false);
  assert.equal(fake.calls.some((c) => c.method === "DELETE"), false);
});

test("an answer for another id deletes nothing; GoTrue's failures are said", async () => {
  const odd = world({ answer: { ok: true, value: { ...plain, user_id: "11311311-0000-0000-0000-000000000099" } } });
  assert.equal((await deleteMe(odd)).status, 403);
  assert.equal(odd.calls.some((c) => c.method === "DELETE"), false);

  const gone = world({ answer: { ok: true, value: plain }, gotrue: [404] });
  assert.equal((await deleteMe(gone)).status, 200);

  // GoTrue refusing even the soft delete: said as a 409 the person can
  // act on, never « réessayez ».
  const broken = world({ answer: { ok: true, value: plain }, gotrue: [500, 500] });
  const out = await deleteMe(broken);
  assert.equal(out.status, 409);
  assert.equal(out.body.error, "La suppression n'a pas pu se faire — écrivez à Mara.");

  const refused = world({ answer: { ok: true, value: plain }, gotrue: [403] });
  const other = await deleteMe(refused);
  assert.equal(other.status, 502);
  assert.equal(other.body.error, "L'opération a échoué. Réessayez.");
});
