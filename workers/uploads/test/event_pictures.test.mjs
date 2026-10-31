// A card's pictures (154): the organiser's editor uploads them signed out,
// with the card's edit token; Postgres mints and confirms every key; the
// street reads them by key once the bytes are in.
//
//   node --test workers/uploads/test
//
// Plays the bucket and PostgREST, as courier_photos.test does. Postgres's
// own rules are test_batch154.sql's; this proves the Worker asks them
// before it touches a byte.

import assert from "node:assert/strict";
import { test } from "node:test";

import worker from "../src/index.js";

const EVENT = "15415415-2222-0000-0000-000000000001";
const EDIT = "ed17ed17ed17ed17ed17ed17";
const KEY = `events/${EVENT}/0123456789abcdef0123456789abcdef.jpg`;
const PHOTO = new Uint8Array(3_000).fill(7);

function bucket(objects = {}) {
  const store = new Map(Object.entries(objects));
  return {
    store,
    puts: [],
    deletes: [],
    async get(key) {
      const entry = store.get(key);
      if (!entry) return null;
      return {
        key,
        httpEtag: `"${key.length}"`,
        body: new Response(entry.bytes).body,
        writeHttpMetadata(headers) { headers.set("Content-Type", entry.type); },
      };
    },
    async put(key, bytes, options) {
      this.puts.push({ key, options });
      store.set(key, { bytes: new Uint8Array(bytes), type: options.httpMetadata.contentType });
    },
    async delete(keys) {
      for (const k of Array.isArray(keys) ? keys : [keys]) {
        this.deletes.push(k);
        store.delete(k);
      }
    },
  };
}

function withPostgres(answers, run) {
  const real = globalThis.fetch;
  const asked = [];
  globalThis.fetch = async (url, init = {}) => {
    const u = new URL(url);
    const name = u.pathname.replace(/^\/rest\/v1\/(rpc\/)?/, "");
    const token = (init.headers?.Authorization || "").replace(/^Bearer /, "");
    const body = init.body ? JSON.parse(init.body) : null;
    asked.push({ name, token, body });
    const answer = answers[name];
    if (!answer) return new Response(JSON.stringify({ message: "not found" }), { status: 404 });
    const [status, value] = answer(body, token);
    return new Response(JSON.stringify(value), { status });
  };
  return run(asked).finally(() => { globalThis.fetch = real; });
}

function env(objects) {
  return {
    SUPABASE_URL: "https://db.example",
    SUPABASE_PUBLISHABLE_KEY: "pub",
    ALLOWED_ORIGINS: "https://marakaj.com",
    UPLOADS: bucket(objects),
  };
}

const upload = (e, { edit = EDIT, slug = "ines-thomas-ab12", type = "image/jpeg", bytes = PHOTO } = {}) =>
  worker.fetch(new Request(`https://up.example/v1/events/${slug}/pictures?modifier=${edit}`, {
    method: "POST",
    headers: { "Content-Type": type, Origin: "https://marakaj.com" },
    body: bytes,
  }), e);

test("a picture: the key minted by Postgres with the token, the bytes put, the key confirmed, the address answered", async () => {
  const e = env();
  await withPostgres({
    event_picture_slot: (body) => body.p_edit === EDIT && body.p_slug === "ines-thomas-ab12" && body.p_ext === "jpg" ? [200, KEY] : [403, { message: "Cette carte ne peut pas être modifiée d'ici." }],
    event_picture_done: (body) => body.p_key === KEY && body.p_edit === EDIT && body.p_bytes === 3000 ? [200, true] : [403, { message: "Envoi inconnu." }],
  }, async (asked) => {
    const r = await upload(e);
    assert.equal(r.status, 201);
    const j = await r.json();
    assert.equal(j.key, KEY);
    assert.equal(j.bytes, 3000);
    assert.equal(j.url, `/v1/public/objects/${encodeURIComponent(KEY)}`);
    assert.deepEqual(asked.map((a) => a.name), ["event_picture_slot", "event_picture_done"]);
    assert.ok(asked.every((a) => a.token === "pub"), "asked as the anonymous role: the token is in the parameters");
    assert.equal(e.UPLOADS.puts.length, 1);
    assert.equal(e.UPLOADS.puts[0].key, KEY);
    assert.equal(e.UPLOADS.puts[0].options.httpMetadata.contentType, "image/jpeg");
    assert.equal(r.headers.get("Access-Control-Allow-Origin"), "https://marakaj.com");
  });
});

test("Postgres refuses the slot: its words, nothing put", async () => {
  const e = env();
  await withPostgres({
    event_picture_slot: () => [403, { message: "Trop d'images pour cette carte : retirez-en avant d'en ajouter." }],
  }, async () => {
    const r = await upload(e);
    assert.equal(r.status, 403);
    assert.equal((await r.json()).error, "Trop d'images pour cette carte : retirez-en avant d'en ajouter.");
    assert.equal(e.UPLOADS.puts.length, 0);
  });
});

test("Postgres refuses the confirmation: the bytes just written are deleted", async () => {
  const e = env();
  await withPostgres({
    event_picture_slot: () => [200, KEY],
    event_picture_done: () => [403, { message: "Envoi inconnu." }],
  }, async () => {
    const r = await upload(e);
    assert.equal(r.status, 403);
    assert.deepEqual(e.UPLOADS.deletes, [KEY]);
    assert.equal(e.UPLOADS.store.size, 0);
  });
});

test("a key Postgres hands back that is not a card's: nothing put", async () => {
  const e = env();
  await withPostgres({
    event_picture_slot: () => [200, "org/6f1c2f8e-1111-4a2b-9c3d-000000000009/2026/10/abc.jpg"],
  }, async () => {
    const r = await upload(e);
    assert.equal(r.status, 500);
    assert.equal(e.UPLOADS.puts.length, 0);
  });
});

test("no token, a malformed token, a PDF, a file too large: refused before Postgres is asked", async () => {
  const e = env();
  await withPostgres({}, async (asked) => {
    assert.equal((await upload(e, { edit: "" })).status, 403);
    assert.equal((await upload(e, { edit: "short" })).status, 403);
    assert.equal((await upload(e, { type: "application/pdf" })).status, 415);
    assert.equal((await upload(e, { type: "image/heic" })).status, 415, "what a card's page sends: JPEG, PNG, WebP");
    const big = new Request("https://up.example/v1/events/x-1/pictures?modifier=" + EDIT, {
      method: "POST",
      headers: { "Content-Type": "image/jpeg", "Content-Length": String(9 * 1024 * 1024), Origin: "https://marakaj.com" },
      body: PHOTO,
    });
    assert.equal((await worker.fetch(big, e)).status, 413);
    assert.equal(asked.length, 0);
    assert.equal(e.UPLOADS.puts.length, 0);
  });
});

test("the street reads a card's picture by key once Postgres says the bytes are in; nothing before", async () => {
  const e = env({ [KEY]: { bytes: PHOTO, type: "image/jpeg" } });
  await withPostgres({
    event_picture_allowed: (body) => [200, body.p_key === KEY],
  }, async (asked) => {
    const r = await worker.fetch(new Request(`https://up.example/v1/public/objects/${encodeURIComponent(KEY)}`), e);
    assert.equal(r.status, 200);
    assert.equal(r.headers.get("Content-Type"), "image/jpeg");
    assert.equal(r.headers.get("Cache-Control"), "public, max-age=3600");
    assert.deepEqual(asked.map((a) => a.name), ["event_picture_allowed"], "a card's key asks the card's rule, not the vitrine's");
    const other = `events/${EVENT}/ffffffffffffffffffffffffffffffff.jpg`;
    const none = await worker.fetch(new Request(`https://up.example/v1/public/objects/${encodeURIComponent(other)}`), e);
    assert.equal(none.status, 404);
  });
});

test("a card's key is never served by the signed-in gallery route, nor a vitrine key by the card's rule", async () => {
  const e = env({ [KEY]: { bytes: PHOTO, type: "image/jpeg" } });
  await withPostgres({
    event_picture_allowed: () => [200, true],
    storefront_photo_allowed: () => [200, false],
  }, async (asked) => {
    const gallery = await worker.fetch(new Request(`https://up.example/v1/objects/${encodeURIComponent(KEY)}`, {
      headers: { Authorization: "Bearer member" },
    }), e);
    assert.equal(gallery.status, 404, "org/ only on that route");
    const vitrine = await worker.fetch(new Request("https://up.example/v1/public/objects/org%2F6f1c2f8e-1111-4a2b-9c3d-000000000009%2F2026%2F10%2Fabc.jpg"), e);
    assert.equal(vitrine.status, 404);
    assert.deepEqual(asked.map((a) => a.name), ["storefront_photo_allowed"], "a vitrine key asks the vitrine's rule");
  });
});
