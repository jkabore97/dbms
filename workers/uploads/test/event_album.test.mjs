// The guests' album (155): a guest with the card's link uploads a picture
// signed out; Postgres mints and confirms every key with that link; the
// business's admin removes one with their own token, and the bytes go.
//
//   node --test workers/uploads/test

import assert from "node:assert/strict";
import { test } from "node:test";

import worker from "../src/index.js";

const EVENT = "15515515-2222-0000-0000-000000000001";
const PREVIEW = "f00df00df00df00df00df00d";
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

const upload = (e, { preview = PREVIEW, guest = "Tanti Rose", slug = "ines-thomas-ab12", type = "image/jpeg", bytes = PHOTO, pass = null, device = null } = {}) =>
  worker.fetch(new Request(`https://up.example/v1/events/${slug}/album?apercu=${preview}&invite=${encodeURIComponent(guest)}${pass === null ? "" : `&pass=${encodeURIComponent(pass)}`}${device === null ? "" : `&device=${encodeURIComponent(device)}`}`, {
    method: "POST",
    headers: { "Content-Type": type, Origin: "https://marakaj.com" },
    body: bytes,
  }), e);

test("a guest's picture: the key minted with the card's link and the name, the bytes put, the key confirmed", async () => {
  const e = env();
  await withPostgres({
    event_album_add: (body) => body.p_preview === PREVIEW && body.p_slug === "ines-thomas-ab12" && body.p_ext === "jpg" && body.p_guest === "Tanti Rose"
      ? [200, KEY] : [403, { message: "Cette carte n'est pas ouverte." }],
    event_album_done: (body) => body.p_key === KEY && body.p_preview === PREVIEW && body.p_bytes === 3000 ? [200, true] : [403, { message: "Envoi inconnu." }],
  }, async (asked) => {
    const r = await upload(e);
    assert.equal(r.status, 201);
    const j = await r.json();
    assert.equal(j.key, KEY);
    assert.equal(j.url, `/v1/public/objects/${encodeURIComponent(KEY)}`);
    assert.deepEqual(asked.map((a) => a.name), ["event_album_add", "event_album_done"]);
    assert.ok(asked.every((a) => a.token === "pub"), "asked as the anonymous role");
    assert.equal(e.UPLOADS.puts.length, 1);
    assert.equal(e.UPLOADS.puts[0].options.customMetadata.guest, "Tanti Rose");
  });
});

test("a published card: no link needed, no name given — Postgres is asked with nulls", async () => {
  const e = env();
  await withPostgres({
    event_album_add: (body) => body.p_preview === null && body.p_guest === null ? [200, KEY] : [403, { message: "no" }],
    event_album_done: (body) => body.p_preview === null ? [200, true] : [403, { message: "no" }],
  }, async () => {
    const r = await upload(e, { preview: "", guest: "" });
    assert.equal(r.status, 201);
  });
});

test("Postgres refuses the slot (album closed): its words, nothing put", async () => {
  const e = env();
  await withPostgres({
    event_album_add: () => [403, { message: "L'album est fermé pour cet événement." }],
  }, async () => {
    const r = await upload(e);
    assert.equal(r.status, 403);
    assert.equal((await r.json()).error, "L'album est fermé pour cet événement.");
    assert.equal(e.UPLOADS.puts.length, 0);
  });
});

test("Postgres refuses the confirmation: the bytes just written are deleted", async () => {
  const e = env();
  await withPostgres({
    event_album_add: () => [200, KEY],
    event_album_done: () => [403, { message: "Envoi inconnu." }],
  }, async () => {
    const r = await upload(e);
    assert.equal(r.status, 403);
    assert.deepEqual(e.UPLOADS.deletes, [KEY]);
  });
});

test("a PDF, a file too large: refused before Postgres is asked; a long name is cut to sixty", async () => {
  const e = env();
  await withPostgres({}, async (asked) => {
    assert.equal((await upload(e, { type: "application/pdf" })).status, 415);
    const big = new Request("https://up.example/v1/events/x-1/album?apercu=" + PREVIEW, {
      method: "POST",
      headers: { "Content-Type": "image/jpeg", "Content-Length": String(9 * 1024 * 1024), Origin: "https://marakaj.com" },
      body: PHOTO,
    });
    assert.equal((await worker.fetch(big, e)).status, 413);
    assert.equal(asked.length, 0);
  });
  await withPostgres({
    event_album_add: (body) => body.p_guest.length === 60 ? [200, KEY] : [403, { message: "long" }],
    event_album_done: () => [200, true],
  }, async () => {
    assert.equal((await upload(e, { guest: "x".repeat(90) })).status, 201);
  });
});

test("the organiser removes a picture: Postgres as the admin, then the bytes go; an employee removes nothing", async () => {
  const e = env({ [KEY]: { bytes: PHOTO, type: "image/jpeg" } });
  await withPostgres({
    event_picture_delete: (body, token) => [200, token === "admin" && body.p_key === KEY],
  }, async (asked) => {
    const del = (token) => worker.fetch(new Request(`https://up.example/v1/objects/${encodeURIComponent(KEY)}`, {
      method: "DELETE",
      headers: { Authorization: `Bearer ${token}`, Origin: "https://marakaj.com" },
    }), e);
    const none = await del("employee");
    assert.equal(none.status, 404, "nothing removed: nothing said about the key");
    assert.equal(e.UPLOADS.deletes.length, 0);
    const r = await del("admin");
    assert.equal(r.status, 204);
    assert.deepEqual(e.UPLOADS.deletes, [KEY]);
    assert.equal(asked.length, 2);
    assert.ok(asked.every((a) => a.name === "event_picture_delete"));
    // Signed out: nothing.
    const anon = await worker.fetch(new Request(`https://up.example/v1/objects/${encodeURIComponent(KEY)}`, { method: "DELETE" }), e);
    assert.equal(anon.status, 401);
    // A vitrine photo is not removed this way.
    const vitrine = await worker.fetch(new Request("https://up.example/v1/objects/org%2F6f1c2f8e-1111-4a2b-9c3d-000000000009%2F2026%2F10%2Fabc.jpg", {
      method: "DELETE", headers: { Authorization: "Bearer admin" },
    }), e);
    assert.equal(vitrine.status, 404);
    assert.equal(asked.length, 2, "Postgres not asked for it");
  });
});

test("164: the guest's pass goes with the picture; anything else is no pass", async () => {
  const PASS = "16416416-4444-0000-0000-000000000001";
  for (const [given, sent] of [[PASS, PASS], [PASS.toUpperCase(), PASS], ["../x", null], ["", null]]) {
    const e = env();
    await withPostgres({
      event_album_add: (body) => body.p_pass === sent ? [200, KEY] : [403, { message: "pass " + body.p_pass }],
      event_album_done: () => [200, true],
    }, async () => {
      const r = await upload(e, { pass: given });
      assert.equal(r.status, 201, `pass ${given}`);
    });
  }
});

test("179: the phone's identifier goes to Postgres when the page sends one, and only a well-formed one", async () => {
  const e = env();
  await withPostgres({
    event_album_add: () => [200, KEY],
    event_album_done: () => [200, true],
  }, async (asked) => {
    await upload(e, { device: "phone-0123456789abcdef" });
    assert.equal(asked[0].body.p_device, "phone-0123456789abcdef");
    await upload(e);
    assert.equal("p_device" in asked[2].body, false, "none sent: none asked (a database before 179)");
    await upload(e, { device: "<script>" });
    assert.equal("p_device" in asked[4].body, false, "a malformed one dropped");
  });
});

// 183: a confirmed guest's photo from the app, signed in — every question
// asked as the guest, five per account counted by Postgres.
const guestUpload = (e, { token = "jwt-nora", slug = "mariage-awa-183", type = "image/jpeg", bytes = PHOTO } = {}) =>
  worker.fetch(new Request(`https://up.example/v1/events/${slug}/album/guest`, {
    method: "POST",
    headers: { "Content-Type": type, ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: bytes,
  }), e);

test("183: a confirmed guest's photo — minted and confirmed as the guest, the bytes put", async () => {
  const e = env();
  await withPostgres({
    event_album_add_guest: (body, token) => token === "jwt-nora" && body.p_slug === "mariage-awa-183" && body.p_ext === "jpg" ? [200, KEY] : [403, { message: "no" }],
    event_album_done: (body, token) => token === "jwt-nora" && body.p_key === KEY && body.p_preview === null && body.p_bytes === 3000 ? [200, true] : [403, { message: "Envoi inconnu." }],
  }, async (asked) => {
    const r = await guestUpload(e);
    assert.equal(r.status, 201);
    assert.equal((await r.json()).key, KEY);
    assert.deepEqual(asked.map((a) => a.name), ["event_album_add_guest", "event_album_done"]);
    assert.ok(asked.every((a) => a.token === "jwt-nora"), "asked as the guest, never the anonymous role");
    assert.equal(e.UPLOADS.puts.length, 1);
  });
});

test("183: the sixth photo — Postgres's words, nothing put; signed out — refused before Postgres", async () => {
  const e = env();
  await withPostgres({
    event_album_add_guest: () => [400, { message: "Vous avez déposé vos 5 photos : c'est le maximum par invité." }],
  }, async (asked) => {
    const r = await guestUpload(e);
    assert.equal(r.status, 403);
    assert.equal((await r.json()).error, "Vous avez déposé vos 5 photos : c'est le maximum par invité.");
    assert.equal(e.UPLOADS.puts.length, 0);
    const out = await guestUpload(e, { token: null });
    assert.equal(out.status, 401);
    assert.equal(asked.length, 1, "signed out: Postgres not asked");
  });
});

test("183: the confirmation refused — the bytes just written are deleted", async () => {
  const e = env();
  await withPostgres({
    event_album_add_guest: () => [200, KEY],
    event_album_done: () => [403, { message: "Envoi inconnu." }],
  }, async () => {
    const r = await guestUpload(e);
    assert.equal(r.status, 403);
    assert.deepEqual(e.UPLOADS.deletes, [KEY]);
  });
});
