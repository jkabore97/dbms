// PostgREST through the site's own address (src/supabase_proxy.js).
//
//   node --test workers/kaj-app/test/*.test.mjs
//
// The project is played by a recording fetch: what it was asked, and an
// answer shaped like PostgREST's.

import assert from "node:assert/strict";
import { test } from "node:test";

import site from "../src/index.js";
import { proxySupabase, upstreamPath } from "../src/supabase_proxy.js";

const PROJECT = "https://abcdefghijklmnop.supabase.example";
const env = {
  SUPABASE_URL: `${PROJECT}/`,
  SUPABASE_PUBLISHABLE_KEY: "sb_publishable_test",
  ASSETS: { fetch: async () => new Response("<html></html>", { headers: { "Content-Type": "text/html" } }) },
};

function recorder(answer = () => new Response("[]", { status: 200 })) {
  const calls = [];
  const fetcher = async (url, init) => {
    const body = init.body ? await new Response(init.body).text() : null;
    calls.push({ url, init, body });
    return answer(url, init);
  };
  return { calls, fetcher };
}

test("only /sb/rest/v1 is passed on; everything else under /sb is not found", () => {
  assert.equal(upstreamPath("/sb/rest/v1/rpc/street"), "/rest/v1/rpc/street");
  assert.equal(upstreamPath("/sb/rest/v1"), "/rest/v1");
  assert.equal(upstreamPath("/sb/rest/v1/"), "/rest/v1/");
  for (const path of [
    "/sb", "/sb/", "/sb/auth/v1/token", "/sb/realtime/v1/websocket", "/sb/storage/v1/object/x",
    "/sb/rest/v10/x", "/sb/rest/v1x", "/sb/functions/v1/x", "/sb/pg/query", "/sbx/rest/v1",
    "/rest/v1/x", "/s/rest/v1",
  ]) {
    assert.equal(upstreamPath(path), null, path);
  }
});

test("a request goes to the project, method, query, headers and body intact", async () => {
  const { calls, fetcher } = recorder();
  const request = new Request("https://marakaj.com/sb/rest/v1/rpc/storefront?select=*&limit=5", {
    method: "POST",
    headers: {
      apikey: "sb_publishable_test",
      Authorization: "Bearer eyJ.user.jwt",
      Prefer: "count=exact",
      Range: "0-9",
      "Content-Type": "application/json",
      "x-client-info": "supabase-flutter/2.17.2",
      "Content-Profile": "public",
      Cookie: "site=1",
      "CF-Connecting-IP": "203.0.113.9",
    },
    body: JSON.stringify({ p_slug: "tony-pizza" }),
  });
  await proxySupabase(request, env, fetcher);
  assert.equal(calls.length, 1);
  const { url, init, body } = calls[0];
  assert.equal(url, `${PROJECT}/rest/v1/rpc/storefront?select=*&limit=5`);
  assert.equal(init.method, "POST");
  assert.equal(init.redirect, "manual");
  assert.equal(init.cache, "no-store");
  assert.equal(body, '{"p_slug":"tony-pizza"}');
  const h = init.headers;
  assert.equal(h.get("apikey"), "sb_publishable_test");
  assert.equal(h.get("authorization"), "Bearer eyJ.user.jwt");
  assert.equal(h.get("prefer"), "count=exact");
  assert.equal(h.get("range"), "0-9");
  assert.equal(h.get("content-type"), "application/json");
  assert.equal(h.get("x-client-info"), "supabase-flutter/2.17.2");
  assert.equal(h.get("content-profile"), "public");
  // The site's own: not the project's business.
  assert.equal(h.get("cookie"), null);
  assert.equal(h.get("cf-connecting-ip"), null);
  assert.equal(h.get("host"), null);
});

test("every method goes through; a GET carries no body", async () => {
  for (const method of ["GET", "HEAD", "POST", "PATCH", "PUT", "DELETE"]) {
    const { calls, fetcher } = recorder();
    const init = { method, headers: { apikey: "k" } };
    if (method !== "GET" && method !== "HEAD") init.body = "{}";
    await proxySupabase(new Request("https://marakaj.com/sb/rest/v1/items?id=eq.1", init), env, fetcher);
    assert.equal(calls[0].init.method, method);
    assert.equal(calls[0].body, init.body ?? null, method);
  }
});

test("the answer comes back as the project gave it: status, range, etag, cookies", async () => {
  const answer = () => {
    const headers = new Headers({
      "Content-Type": "application/json; charset=utf-8",
      "Content-Range": "0-9/42",
      ETag: 'W/"abc"',
      "Preference-Applied": "count=exact",
    });
    headers.append("Set-Cookie", "a=1; Path=/");
    headers.append("Set-Cookie", "b=2; Path=/");
    return new Response('[{"id":1}]', { status: 206, headers });
  };
  const { fetcher } = recorder(answer);
  const r = await proxySupabase(new Request("https://marakaj.com/sb/rest/v1/items", { headers: { Range: "0-9" } }), env, fetcher);
  assert.equal(r.status, 206);
  assert.equal(await r.text(), '[{"id":1}]');
  assert.equal(r.headers.get("content-range"), "0-9/42");
  assert.equal(r.headers.get("etag"), 'W/"abc"');
  assert.equal(r.headers.get("preference-applied"), "count=exact");
  assert.deepEqual(r.headers.getSetCookie(), ["a=1; Path=/", "b=2; Path=/"]);
  // Nothing added: no caching, none of the site's own headers.
  assert.equal(r.headers.get("cache-control"), null);
  assert.equal(r.headers.get("x-frame-options"), null);
});

test("errors and redirects are passed back, not followed or rewritten", async () => {
  for (const status of [301, 400, 401, 403, 404, 409, 500]) {
    const { fetcher } = recorder(() => new Response('{"message":"x"}', {
      status,
      headers: status === 301 ? { Location: "https://elsewhere.example/" } : {},
    }));
    const r = await proxySupabase(new Request("https://marakaj.com/sb/rest/v1/x"), env, fetcher);
    assert.equal(r.status, status);
  }
});

test("never an open proxy: the upstream is SUPABASE_URL's host, whatever the request says", async () => {
  const { calls, fetcher } = recorder();
  for (const path of [
    "/sb/rest/v1/../../auth/v1/token",
    "/sb/rest/v1/%2e%2e/%2e%2e/auth/v1/admin/users",
    "//evil.example/sb/rest/v1/x",
  ]) {
    await proxySupabase(new Request(`https://marakaj.com${path}`, { headers: { Host: "evil.example" } }), env, fetcher);
  }
  for (const { url } of calls) {
    assert.ok(url.startsWith(`${PROJECT}/rest/v1/`), url);
  }
  // The parser resolves « .. » first: what is left is not PostgREST.
  const r = await proxySupabase(new Request("https://marakaj.com/sb/rest/v1/../../auth/v1/token"), env, recorder().fetcher);
  assert.equal(r.status, 404);
  // Absolute URLs in the path stay paths on the project.
  const odd = recorder();
  await proxySupabase(new Request("https://marakaj.com/sb/rest/v1/https://evil.example/x"), env, odd.fetcher);
  assert.equal(new URL(odd.calls[0].url).host, new URL(PROJECT).host);
});

test("no SUPABASE_URL: « not configured », nothing is fetched", async () => {
  for (const value of [undefined, "", "   ", "not a url", "ftp://x.example"]) {
    const { calls, fetcher } = recorder();
    const r = await proxySupabase(new Request("https://marakaj.com/sb/rest/v1/x"), { SUPABASE_URL: value }, fetcher);
    assert.equal(r.status, 503, String(value));
    assert.equal(r.headers.get("cache-control"), "no-store");
    assert.equal(calls.length, 0);
  }
});

test("the project out of reach: 502, never the app's page", async () => {
  const r = await proxySupabase(new Request("https://marakaj.com/sb/rest/v1/x"), env, async () => {
    throw new TypeError("network");
  });
  assert.equal(r.status, 502);
});

test("the site sends /sb/ to the proxy, never to the app's files", async () => {
  // Through the site's own fetch, with the platform's fetch stubbed.
  const real = globalThis.fetch;
  const seen = [];
  globalThis.fetch = async (url, init) => {
    seen.push(url);
    return new Response("[]", { status: 200, headers: { "Content-Type": "application/json" } });
  };
  try {
    const ok = await site.fetch(new Request("https://marakaj.com/sb/rest/v1/rpc/street", { method: "POST", body: "{}" }), env);
    assert.equal(ok.status, 200);
    assert.equal(await ok.text(), "[]");
    assert.equal(ok.headers.get("x-frame-options"), null);
    const no = await site.fetch(new Request("https://marakaj.com/sb/auth/v1/token?grant_type=refresh_token", { method: "POST", body: "{}" }), env);
    assert.equal(no.status, 404);
    assert.notEqual(no.headers.get("content-type"), "text/html");
    assert.deepEqual(seen, [`${PROJECT}/rest/v1/rpc/street`]);
    // The old address still redirects first.
    const old = await site.fetch(new Request("https://dbms.kabore-boss.workers.dev/sb/rest/v1/x"), env);
    assert.equal(old.status, 301);
  } finally {
    globalThis.fetch = real;
  }
});

test("a websocket upgrade is not proxied (realtime stays direct)", async () => {
  const { calls, fetcher } = recorder();
  const r = await proxySupabase(
    new Request("https://marakaj.com/sb/realtime/v1/websocket?apikey=k&vsn=1.0.0", { headers: { Upgrade: "websocket" } }),
    env,
    fetcher,
  );
  assert.equal(r.status, 404);
  assert.equal(calls.length, 0);
});
