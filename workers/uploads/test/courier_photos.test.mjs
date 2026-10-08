// A courier's dossier (112): its photos private, through every route.
//
//   node --test workers/uploads/test
//
// Plays the bucket (an in-memory R2 that records gets, puts and deletes)
// and PostgREST (a fake that answers each RPC or table read by name, and
// records the token it was asked with) — no network. Postgres's own rules
// are test_batch112.sql's; this proves the Worker asks them, as the
// caller, before it touches a byte, and that no other route serves one.

import assert from "node:assert/strict";
import { test } from "node:test";

import worker from "../src/index.js";

const UID = "11211211-0000-0000-0000-000000000002";
const KEY = `courier/${UID}/6f1c2f8e-1111-4a2b-9c3d-000000000001.jpg`;
const ORG_KEY = "org/6f1c2f8e-1111-4a2b-9c3d-000000000009/2026/10/abc.jpg";
const SELFIE = new Uint8Array(4_000).fill(9);

function bucket(objects = {}) {
  const store = new Map(Object.entries(objects));
  return {
    store,
    gets: [],
    puts: [],
    deletes: [],
    async get(key) {
      this.gets.push(key);
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

// answers: { fnOrTable: (body, token) => [status, json] }
function withPostgres(answers, run) {
  const real = globalThis.fetch;
  const asked = [];
  globalThis.fetch = async (url, init = {}) => {
    const u = new URL(url);
    const name = u.pathname.replace(/^\/rest\/v1\/(rpc\/)?/, "");
    const token = (init.headers?.Authorization || "").replace(/^Bearer /, "");
    const body = init.body ? JSON.parse(init.body) : null;
    asked.push({ name, token, body, query: u.search });
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

const upload = (e, { token = "applicant", part = "selfie", type = "image/jpeg", bytes = SELFIE } = {}) =>
  worker.fetch(new Request(`https://up.example/v1/courier/uploads?part=${part}`, {
    method: "POST",
    headers: {
      Origin: "https://marakaj.com",
      "Content-Type": type,
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: bytes,
  }), e);

const read = (e, key, { token, method = "GET", route = "courier/objects" } = {}) =>
  worker.fetch(new Request(`https://up.example/v1/${route}/${encodeURIComponent(key)}`, {
    method,
    headers: token ? { Authorization: `Bearer ${token}` } : {},
  }), e);

test("upload: the key is Postgres's, asked as the applicant; the bytes land; done is said; no key comes back", async () => {
  const e = env();
  await withPostgres({
    courier_upload_slot: (body) => [200, `courier/${UID}/6f1c2f8e-1111-4a2b-9c3d-00000000000${body.p_part === "selfie" ? 1 : 2}.${body.p_ext}`],
    courier_upload_done: () => [200, "selfie"],
  }, async (asked) => {
    const r = await upload(e);
    assert.equal(r.status, 201);
    assert.deepEqual(await r.json(), { part: "selfie", bytes: SELFIE.byteLength });
    assert.deepEqual(asked.map((a) => [a.name, a.token]), [
      ["courier_upload_slot", "applicant"],
      ["courier_upload_done", "applicant"],
    ]);
    assert.deepEqual(asked[0].body, { p_part: "selfie", p_ext: "jpg" });
    assert.deepEqual(asked[1].body, { p_key: KEY });
    assert.deepEqual(e.UPLOADS.puts.map((p) => p.key), [KEY]);
    assert.equal(e.UPLOADS.puts[0].options.httpMetadata.contentType, "image/jpeg");
    assert.equal(r.headers.get("Access-Control-Allow-Origin"), "https://marakaj.com");
  });
});

test("upload: signed out, a strange part, a PDF or a page — refused before Postgres or the bucket", async () => {
  const e = env();
  await withPostgres({}, async (asked) => {
    assert.equal((await upload(e, { token: null })).status, 401);
    assert.equal((await upload(e, { part: "passport" })).status, 400);
    const pdf = await upload(e, { type: "application/pdf" });
    assert.equal(pdf.status, 415);
    assert.equal((await pdf.json()).error, "Photos uniquement.");
    assert.equal((await upload(e, { type: "text/html" })).status, 415);
    assert.equal((await upload(e, { type: "image/svg+xml" })).status, 415);
    assert.equal(asked.length, 0);
    assert.equal(e.UPLOADS.puts.length, 0);
  });
});

test("upload: Postgres's no is said in its words, and nothing is written", async () => {
  const e = env();
  await withPostgres({
    courier_upload_slot: () => [400, { code: "P0001", message: "Votre demande est en cours d'examen" }],
  }, async () => {
    const r = await upload(e);
    assert.equal(r.status, 403);
    assert.equal((await r.json()).error, "Votre demande est en cours d'examen");
    assert.equal(e.UPLOADS.puts.length, 0);
  });
  // An expired token: « connectez-vous ».
  await withPostgres({ courier_upload_slot: () => [401, { message: "JWT expired" }] }, async () => {
    assert.equal((await upload(e)).status, 401);
  });
});

test("upload: a key not shaped like a courier key is never written (an org/ key, a traversal)", async () => {
  for (const bad of [ORG_KEY, `courier/${UID}/../x.jpg`, `courier/other/${UID}.jpg`, null]) {
    const e = env();
    await withPostgres({ courier_upload_slot: () => [200, bad] }, async () => {
      assert.equal((await upload(e)).status, 500);
      assert.equal(e.UPLOADS.puts.length, 0);
    });
  }
});

test("upload: done refused — the bytes just written are taken back", async () => {
  const e = env();
  await withPostgres({
    courier_upload_slot: () => [200, KEY],
    courier_upload_done: () => [400, { message: "Envoi inconnu" }],
  }, async () => {
    const r = await upload(e);
    assert.equal(r.status, 403);
    assert.deepEqual(e.UPLOADS.deletes, [KEY]);
    assert.equal(e.UPLOADS.store.has(KEY), false);
  });
});

test("read: only with Postgres's yes, asked as the caller; never cached; HEAD has no body", async () => {
  const e = env({ [KEY]: { bytes: SELFIE, type: "image/jpeg" } });
  await withPostgres({
    courier_photo_allowed: (body, token) => [200, token === "admin" && body.p_key === KEY],
  }, async (asked) => {
    const r = await read(e, KEY, { token: "admin" });
    assert.equal(r.status, 200);
    assert.equal((await r.arrayBuffer()).byteLength, SELFIE.byteLength);
    assert.equal(r.headers.get("Cache-Control"), "private, no-store");
    assert.equal(r.headers.get("X-Content-Type-Options"), "nosniff");
    assert.equal(r.headers.get("Referrer-Policy"), "no-referrer");
    assert.equal(r.headers.get("Content-Security-Policy"), "default-src 'none'; sandbox");
    assert.deepEqual(asked.map((a) => [a.name, a.token, a.body.p_key]), [["courier_photo_allowed", "admin", KEY]]);
    const head = await read(e, KEY, { token: "admin", method: "HEAD" });
    assert.equal(head.status, 200);
    assert.equal(head.body, null);
  });
});

test("read: the applicant, another person, a business owner — Postgres says no: a 404, the bucket untouched", async () => {
  const e = env({ [KEY]: { bytes: SELFIE, type: "image/jpeg" } });
  await withPostgres({ courier_photo_allowed: () => [200, false] }, async () => {
    for (const token of ["applicant", "stranger", "shop-owner", "farm-owner", "association-owner"]) {
      const r = await read(e, KEY, { token });
      assert.equal(r.status, 404, token);
      assert.equal((await r.json()).error, "Introuvable.");
    }
    assert.equal(e.UPLOADS.gets.length, 0);
  });
  // Postgres failing, or a token it rejects: no photo either.
  await withPostgres({ courier_photo_allowed: () => [401, { message: "JWT expired" }] }, async () => {
    assert.equal((await read(e, KEY, { token: "expired" })).status, 404);
    assert.equal(e.UPLOADS.gets.length, 0);
  });
});

test("read: signed out — no token, a 401, nobody asked", async () => {
  const e = env({ [KEY]: { bytes: SELFIE, type: "image/jpeg" } });
  await withPostgres({}, async (asked) => {
    const r = await read(e, KEY, {});
    assert.equal(r.status, 401);
    assert.equal(asked.length, 0);
    assert.equal(e.UPLOADS.gets.length, 0);
  });
});

test("no other route serves a courier photo — even if Postgres would say yes", async () => {
  const e = env({
    [KEY]: { bytes: SELFIE, type: "image/jpeg" },
    [`thumb/w400/${KEY}`]: { bytes: SELFIE, type: "image/webp" },
  });
  // A Postgres that says yes to everything: a documents row for any key,
  // storefront_photo_allowed true for any key.
  await withPostgres({
    documents: () => [200, [{ id: "d1" }]],
    storefront_photo_allowed: () => [200, true],
    courier_photo_allowed: () => [200, true],
  }, async (asked) => {
    // The members' gallery route.
    assert.equal((await read(e, KEY, { token: "member", route: "objects" })).status, 404);
    // The street's route, original and thumbnail.
    assert.equal((await read(e, KEY, { route: "public/objects" })).status, 404);
    assert.equal((await worker.fetch(new Request(
      `https://up.example/v1/public/objects/${encodeURIComponent(KEY)}?w=400`), e)).status, 404);
    assert.equal((await read(e, `thumb/w400/${KEY}`, { route: "public/objects" })).status, 404);
    // A key that spells its way out of org/ into courier/.
    for (const sneaky of [`org/../${KEY}`, `org/./../${KEY}`, `org//../${KEY}`, `org/x\\..\\${KEY}`]) {
      assert.equal((await read(e, sneaky, { token: "member", route: "objects" })).status, 404, sneaky);
      assert.equal((await read(e, sneaky, { route: "public/objects" })).status, 404, sneaky);
    }
    // An org key through the courier route: not a courier key.
    assert.equal((await read(e, ORG_KEY, { token: "admin" })).status, 404);
    assert.equal(e.UPLOADS.gets.length, 0, "the bucket was never read");
    assert.equal(asked.length, 0, "Postgres was never even asked");
  });
});

test("purge: Postgres names what is due, as the caller; only courier keys are deleted; then forgotten", async () => {
  const due = [KEY, `courier/${UID}/6f1c2f8e-1111-4a2b-9c3d-000000000003.png`];
  const e = env({
    [due[0]]: { bytes: SELFIE, type: "image/jpeg" },
    [due[1]]: { bytes: SELFIE, type: "image/png" },
    [ORG_KEY]: { bytes: SELFIE, type: "image/jpeg" },
  });
  await withPostgres({
    // A list with an org photo smuggled in: never deleted.
    courier_files_due: () => [200, [...due, ORG_KEY, "courier/../org/x.jpg"]],
    courier_files_purged: (body) => [200, body.p_keys.length],
  }, async (asked) => {
    const r = await worker.fetch(new Request("https://up.example/v1/courier/purge", {
      method: "POST", headers: { Authorization: "Bearer admin" } }), e);
    assert.equal(r.status, 200);
    assert.deepEqual(await r.json(), { deleted: 2 });
    assert.deepEqual(e.UPLOADS.deletes, due);
    assert.equal(e.UPLOADS.store.has(ORG_KEY), true);
    assert.deepEqual(asked.map((a) => [a.name, a.token]), [
      ["courier_files_due", "admin"],
      ["courier_files_purged", "admin"],
    ]);
    assert.deepEqual(asked[1].body, { p_keys: due });
  });
});

test("purge: signed out a 401; nothing due, nothing deleted; Postgres's no, nothing deleted", async () => {
  const e = env({ [KEY]: { bytes: SELFIE, type: "image/jpeg" } });
  await withPostgres({}, async (asked) => {
    const r = await worker.fetch(new Request("https://up.example/v1/courier/purge", { method: "POST" }), e);
    assert.equal(r.status, 401);
    assert.equal(asked.length, 0);
  });
  await withPostgres({ courier_files_due: () => [200, []] }, async (asked) => {
    const r = await worker.fetch(new Request("https://up.example/v1/courier/purge", {
      method: "POST", headers: { Authorization: "Bearer applicant" } }), e);
    assert.deepEqual(await r.json(), { deleted: 0 });
    assert.equal(asked.length, 1);
  });
  await withPostgres({ courier_files_due: () => [400, { message: "Connectez-vous d'abord" }] }, async () => {
    const r = await worker.fetch(new Request("https://up.example/v1/courier/purge", {
      method: "POST", headers: { Authorization: "Bearer x" } }), e);
    assert.equal(r.status, 403);
  });
  assert.equal(e.UPLOADS.deletes.length, 0);
});

test("the org routes keep working for an org photo", async () => {
  const e = env({ [ORG_KEY]: { bytes: SELFIE, type: "image/jpeg" } });
  await withPostgres({ documents: () => [200, [{ id: "d1" }]], storefront_photo_allowed: () => [200, true] }, async () => {
    assert.equal((await read(e, ORG_KEY, { token: "member", route: "objects" })).status, 200);
    assert.equal((await read(e, ORG_KEY, { route: "public/objects" })).status, 200);
  });
});
