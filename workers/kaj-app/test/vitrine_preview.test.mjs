// A vitrine's link preview asks Supabase with GET, which the edge can keep
// (src/index.js, rpc).
//
//   node --test workers/kaj-app/test/*.test.mjs

import assert from "node:assert/strict";
import { test } from "node:test";

import site, { rpcUrl } from "../src/index.js";

const env = {
  SUPABASE_URL: "https://abcdefghijklmnop.supabase.example/",
  SUPABASE_PUBLISHABLE_KEY: "sb_publishable_test",
  ASSETS: { fetch: async () => new Response("<html><head></head></html>", { headers: { "Content-Type": "text/html" } }) },
};

test("the RPC's arguments travel in the query string", () => {
  assert.equal(
    rpcUrl(env, "storefront", { p_slug: "tony-pizza" }),
    "https://abcdefghijklmnop.supabase.example/rest/v1/rpc/storefront?p_slug=tony-pizza",
  );
});

test("/s/<slug> asks for the shop and its articles with GET, kept five minutes", async () => {
  const real = globalThis.fetch;
  const calls = [];
  globalThis.fetch = async (url, init) => {
    calls.push({ url, init });
    return new Response("[]", { headers: { "Content-Type": "application/json" } });
  };
  try {
    const r = await site.fetch(new Request("https://marakaj.com/s/tony-pizza"), env);
    assert.equal(r.status, 200);
  } finally {
    globalThis.fetch = real;
  }
  assert.deepEqual(calls.map((c) => c.url).sort(), [
    "https://abcdefghijklmnop.supabase.example/rest/v1/rpc/storefront?p_slug=tony-pizza",
    "https://abcdefghijklmnop.supabase.example/rest/v1/rpc/storefront_products?p_slug=tony-pizza",
  ]);
  for (const { init } of calls) {
    assert.equal(init.method, "GET");
    assert.equal(init.body, undefined);
    assert.equal(init.headers.apikey, "sb_publishable_test");
    assert.equal(init.cf.cacheTtl, 300);
  }
});
