// The street's photos, small: GET /v1/public/objects/<key>?w=…
//
//   node --test workers/uploads/test
//
// Plays the bucket (an in-memory R2), Cloudflare Images (a fake that
// records what it was asked and answers fewer bytes), and Postgres's
// storefront_photo_allowed (052) — no network.

import assert from "node:assert/strict";
import { test } from "node:test";

import worker from "../src/index.js";

const KEY = "org/6f1c2f8e-1111-4a2b-9c3d-000000000001/2026/01/abc.jpg";
const BIG = new Uint8Array(500_000).fill(7);

function bucket(objects) {
  const store = new Map(Object.entries(objects));
  const object = (key, entry) => ({
    key,
    size: entry.bytes.byteLength,
    httpEtag: `"${key.length}-${entry.bytes.byteLength}"`,
    httpMetadata: { contentType: entry.type },
    body: new Response(entry.bytes).body,
    writeHttpMetadata(headers) { headers.set("Content-Type", entry.type); },
  });
  return {
    store,
    puts: [],
    async get(key) {
      const entry = store.get(key);
      return entry ? object(key, entry) : null;
    },
    async put(key, bytes, options) {
      this.puts.push(key);
      store.set(key, { bytes: new Uint8Array(bytes), type: options.httpMetadata.contentType });
    },
  };
}

function images({ fail = false } = {}) {
  const calls = [];
  return {
    calls,
    input(stream) {
      const chain = {
        transform(options) { calls.push(options); return chain; },
        async output(options) {
          if (fail) throw new Error("9422: transformation limit");
          calls.push(options);
          await new Response(stream).arrayBuffer();
          return { response: () => new Response(new Uint8Array(20_000).fill(1)) };
        },
      };
      return chain;
    },
  };
}

function withPostgres(allowed, run) {
  const real = globalThis.fetch;
  const asked = [];
  globalThis.fetch = async (url, init) => {
    asked.push({ url, body: JSON.parse(init.body) });
    return new Response(JSON.stringify(allowed), { status: 200 });
  };
  return run(asked).finally(() => { globalThis.fetch = real; });
}

function env(extra) {
  return {
    SUPABASE_URL: "https://db.example",
    SUPABASE_PUBLISHABLE_KEY: "pub",
    ALLOWED_ORIGINS: "https://marakaj.com",
    UPLOADS: bucket({ [KEY]: { bytes: BIG, type: "image/jpeg" } }),
    ...extra,
  };
}

const get = (e, query = "") => worker.fetch(
  new Request(`https://up.example/v1/public/objects/${encodeURIComponent(KEY)}${query}`,
    { headers: { Origin: "https://marakaj.com" } }), e);

test("?w=400 answers a WebP made once and kept under thumb/", async () => {
  const e = env({ IMAGES: images() });
  await withPostgres(true, async (asked) => {
    const first = await get(e, "?w=400");
    assert.equal(first.status, 200);
    assert.equal(first.headers.get("Content-Type"), "image/webp");
    assert.equal((await first.arrayBuffer()).byteLength, 20_000);
    assert.deepEqual(e.UPLOADS.puts, [`thumb/w400/${KEY}`]);
    assert.deepEqual(e.IMAGES.calls[0], { width: 400, fit: "scale-down" });

    // The next shopper: the kept copy, no second transformation.
    const again = await get(e, "?w=400");
    assert.equal((await again.arrayBuffer()).byteLength, 20_000);
    assert.equal(e.UPLOADS.puts.length, 1);
    assert.equal(e.IMAGES.calls.length, 2); // one transform + one output, once
    // Postgres was asked about the photo itself, every time.
    assert.deepEqual(asked.map((a) => a.body.p_key), [KEY, KEY]);
    assert.equal(again.headers.get("Cache-Control"), "public, max-age=3600");
    assert.equal(again.headers.get("Access-Control-Allow-Origin"), "https://marakaj.com");
  });
});

test("a width between the allowed ones is rounded up; nonsense means the original", async () => {
  const e = env({ IMAGES: images() });
  await withPostgres(true, async () => {
    await (await get(e, "?w=301")).arrayBuffer();
    assert.deepEqual(e.UPLOADS.puts, [`thumb/w400/${KEY}`]);
    const huge = await get(e, "?w=5000");
    assert.equal(huge.headers.get("Content-Type"), "image/jpeg");
    assert.equal((await huge.arrayBuffer()).byteLength, BIG.byteLength);
    const junk = await get(e, "?w=abc");
    assert.equal((await junk.arrayBuffer()).byteLength, BIG.byteLength);
  });
});

test("no thumbnail without Postgres's yes — a 404 like any unknown key", async () => {
  const e = env({ IMAGES: images() });
  await withPostgres(false, async () => {
    const r = await get(e, "?w=400");
    assert.equal(r.status, 404);
    assert.equal(e.UPLOADS.puts.length, 0);
    assert.equal(e.IMAGES.calls.length, 0);
  });
});

test("no Images binding, or Images refusing: the original, never an error", async () => {
  for (const extra of [{}, { IMAGES: images({ fail: true }) }]) {
    const e = env(extra);
    await withPostgres(true, async () => {
      const r = await get(e, "?w=400");
      assert.equal(r.status, 200);
      assert.equal(r.headers.get("Content-Type"), "image/jpeg");
      assert.equal((await r.arrayBuffer()).byteLength, BIG.byteLength);
      assert.equal(e.UPLOADS.puts.length, 0);
    });
  }
});

test("without ?w= nothing changes: the original, untouched", async () => {
  const e = env({ IMAGES: images() });
  await withPostgres(true, async () => {
    const r = await get(e);
    assert.equal(r.headers.get("Content-Type"), "image/jpeg");
    assert.equal((await r.arrayBuffer()).byteLength, BIG.byteLength);
    assert.equal(e.IMAGES.calls.length, 0);
  });
});

test("thumb/ is never served directly, by either route", async () => {
  const e = env({ IMAGES: images() });
  e.UPLOADS.store.set(`thumb/w400/${KEY}`, { bytes: new Uint8Array(10), type: "image/webp" });
  await withPostgres(true, async () => {
    const pub = await worker.fetch(new Request(
      `https://up.example/v1/public/objects/${encodeURIComponent(`thumb/w400/${KEY}`)}`), e);
    assert.equal(pub.status, 404);
    const priv = await worker.fetch(new Request(
      `https://up.example/v1/objects/${encodeURIComponent(`thumb/w400/${KEY}`)}`,
      { headers: { Authorization: "Bearer t" } }), e);
    assert.equal(priv.status, 404);
  });
});

test("a PDF on an article is not made into a picture", async () => {
  const e = env({ IMAGES: images() });
  e.UPLOADS.store.set(KEY, { bytes: BIG, type: "application/pdf" });
  await withPostgres(true, async () => {
    const r = await get(e, "?w=200");
    assert.equal(r.headers.get("Content-Type"), "application/pdf");
    assert.equal(e.IMAGES.calls.length, 0);
    await r.arrayBuffer();
  });
});
