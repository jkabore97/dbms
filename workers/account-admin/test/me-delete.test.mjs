// Plays PostgREST and GoTrue against workers/account-admin's « Supprimer
// mon compte » (113) — no network.
//
//   node --test workers/account-admin/test
//
// The rule the Worker keeps: Postgres decides, as the caller; the
// service-role key only performs. A fake fetch answers the three places
// the Worker talks to — the caller's rpc, the profile read with the key,
// GoTrue's admin delete — and records each call.

import assert from "node:assert/strict";
import { test } from "node:test";

import worker from "../src/index.js";

const ME = "11311311-0000-0000-0000-000000000005";
const env = {
  SUPABASE_URL: "https://db.example",
  SUPABASE_PUBLISHABLE_KEY: "anon-key",
  SUPABASE_SERVICE_ROLE_KEY: "service-key",
  ALLOWED_ORIGINS: "https://marakaj.com",
};

/// A fake Supabase: [check] is what delete_my_account_check answers.
function supabase({ check, admin = false, gotrue = 200 } = {}) {
  const calls = [];
  const fetch = async (url, init = {}) => {
    const u = new URL(url);
    const auth = (init.headers || {}).Authorization;
    calls.push({ path: u.pathname, method: init.method || "GET", auth, query: u.search });
    if (u.pathname === "/rest/v1/rpc/delete_my_account_check") {
      if (auth !== "Bearer person-token") {
        return new Response(JSON.stringify({ code: "PGRST301", message: "JWT expired" }), { status: 401 });
      }
      return check.ok
        ? new Response(JSON.stringify(check.value), { status: 200 })
        : new Response(JSON.stringify({ code: "P0001", message: check.refused }), { status: 400 });
    }
    if (u.pathname === "/rest/v1/profiles") {
      assert.equal(auth, "Bearer service-key");
      return new Response(JSON.stringify([{ is_platform_admin: admin }]), { status: 200 });
    }
    if (u.pathname.startsWith("/auth/v1/admin/users/")) {
      assert.equal(auth, "Bearer service-key");
      return new Response("{}", { status: gotrue });
    }
    throw new Error(`unexpected call ${u.pathname}`);
  };
  return { calls, fetch };
}

async function deleteMe(fake, { token = "person-token", body = "{}", e = env } = {}) {
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
      body,
    }), e);
    return { status: res.status, body: await res.json(), cors: res.headers.get("Access-Control-Allow-Origin") };
  } finally {
    globalThis.fetch = saved;
  }
}

test("the answered id, and only it, is deleted", async () => {
  const fake = supabase({ check: { ok: true, value: ME } });
  // Whatever the request body names, it is not read.
  const out = await deleteMe(fake, { body: JSON.stringify({ user_id: "someone-else" }) });
  assert.equal(out.status, 200);
  assert.deepEqual(out.body, { ok: true });
  assert.equal(out.cors, "https://marakaj.com");
  const del = fake.calls.filter((c) => c.method === "DELETE");
  assert.equal(del.length, 1);
  assert.equal(del[0].path, `/auth/v1/admin/users/${ME}`);
  // Asked as the caller first, with the caller's own token.
  assert.equal(fake.calls[0].path, "/rest/v1/rpc/delete_my_account_check");
  assert.equal(fake.calls[0].auth, "Bearer person-token");
});

test("the database's refusal is said in its words, and nothing is deleted", async () => {
  const refused = "Une commande est en cours : attendez qu'elle soit terminée, ou annulez-la, puis supprimez votre compte.";
  const fake = supabase({ check: { ok: false, refused } });
  const out = await deleteMe(fake);
  assert.equal(out.status, 409);
  assert.equal(out.body.error, refused);
  assert.equal(fake.calls.some((c) => c.method === "DELETE"), false);
});

test("no token, an expired token, or no key: nothing is asked of GoTrue", async () => {
  const none = supabase({ check: { ok: true, value: ME } });
  assert.equal((await deleteMe(none, { token: null })).status, 401);
  assert.equal(none.calls.length, 0);

  const expired = supabase({ check: { ok: true, value: ME } });
  const out = await deleteMe(expired, { token: "old-token" });
  assert.equal(out.status, 401);
  assert.equal(expired.calls.some((c) => c.method === "DELETE"), false);

  const dormant = supabase({ check: { ok: true, value: ME } });
  const { SUPABASE_SERVICE_ROLE_KEY: _, ...noKey } = env;
  assert.equal((await deleteMe(dormant, { e: noKey })).status, 501);
  assert.equal(dormant.calls.length, 0);
});

test("a platform account is never deleted, even if the answer said yes", async () => {
  const fake = supabase({ check: { ok: true, value: ME }, admin: true });
  const out = await deleteMe(fake);
  assert.equal(out.status, 403);
  assert.equal(fake.calls.some((c) => c.method === "DELETE"), false);
});

test("an answer that is not an id deletes nothing; GoTrue's failure is said", async () => {
  const odd = supabase({ check: { ok: true, value: true } });
  assert.equal((await deleteMe(odd)).status, 403);
  assert.equal(odd.calls.some((c) => c.method === "DELETE"), false);

  const gone = supabase({ check: { ok: true, value: ME }, gotrue: 404 });
  assert.equal((await deleteMe(gone)).status, 200);

  const broken = supabase({ check: { ok: true, value: ME }, gotrue: 500 });
  const out = await deleteMe(broken);
  assert.equal(out.status, 502);
  assert.equal(out.body.error, "L'opération a échoué. Réessayez.");
});
