// The card's own picture (177): Studio draws the card and sends it signed
// out with the edit token; Postgres mints and confirms the key as the
// card's preview and names the one it replaces, whose bytes go.
//
//   node --test workers/uploads/test

import assert from "node:assert/strict";
import { test } from "node:test";

import worker from "../src/index.js";

const EVENT = "17717717-2222-0000-0000-000000000001";
const EDIT = "ed17ed17ed17ed17ed17ed17";
const KEY = `events/${EVENT}/0123456789abcdef0123456789abcdef.jpg`;
const OLD = `events/${EVENT}/fedcba9876543210fedcba9876543210.jpg`;
const PHOTO = new Uint8Array(3_000).fill(7);

function bucket(objects = {}) {
  const store = new Map(Object.entries(objects));
  return {
    store, puts: [], deletes: [],
    async put(key, bytes, options) { this.puts.push({ key, options }); store.set(key, { bytes: new Uint8Array(bytes) }); },
    async delete(k) { this.deletes.push(k); store.delete(k); },
  };
}

function withPostgres(answers, run) {
  const real = globalThis.fetch;
  const asked = [];
  globalThis.fetch = async (url, init = {}) => {
    const name = new URL(url).pathname.replace(/^\/rest\/v1\/(rpc\/)?/, "");
    const body = init.body ? JSON.parse(init.body) : null;
    asked.push({ name, body });
    const answer = answers[name];
    if (!answer) return new Response(JSON.stringify({ message: "not found" }), { status: 404 });
    const [status, value] = answer(body);
    return new Response(JSON.stringify(value), { status });
  };
  return run(asked).finally(() => { globalThis.fetch = real; });
}

const env = (objects) => ({ SUPABASE_URL: "https://db.example", SUPABASE_PUBLISHABLE_KEY: "pub", ALLOWED_ORIGINS: "https://marakaj.com", UPLOADS: bucket(objects) });
const send = (e, edit = EDIT) => worker.fetch(new Request(`https://up.example/v1/events/awa-paul-ab12/preview?modifier=${edit}`, {
  method: "POST", headers: { "Content-Type": "image/jpeg", Origin: "https://marakaj.com" }, body: PHOTO,
}), e);

test("a preview: minted and confirmed as the card's, the one it replaces deleted", async () => {
  const e = env({ [OLD]: { bytes: new Uint8Array(3) } });
  await withPostgres({
    event_preview_slot: (b) => b.p_edit === EDIT && b.p_slug === "awa-paul-ab12" && b.p_ext === "jpg" ? [200, KEY] : [403, { message: "non" }],
    event_preview_done: (b) => b.p_key === KEY && b.p_edit === EDIT && b.p_bytes === 3000 ? [200, OLD] : [403, { message: "Envoi inconnu." }],
  }, async (asked) => {
    const r = await send(e);
    assert.equal(r.status, 201);
    assert.equal((await r.json()).key, KEY);
    assert.deepEqual(asked.map((a) => a.name), ["event_preview_slot", "event_preview_done"]);
    assert.ok(e.UPLOADS.store.has(KEY), "the new one kept");
    assert.deepEqual(e.UPLOADS.deletes, [OLD], "the old one's bytes gone");
  });
});

test("the first preview: nothing to delete; a refusal: its words, nothing kept; a bad token never asks", async () => {
  const e = env();
  await withPostgres({
    event_preview_slot: () => [200, KEY],
    event_preview_done: () => [200, null],
  }, async () => {
    assert.equal((await send(e)).status, 201);
    assert.deepEqual(e.UPLOADS.deletes, []);
  });
  const e2 = env();
  await withPostgres({
    event_preview_slot: () => [200, KEY],
    event_preview_done: () => [400, { message: "Envoi inconnu." }],
  }, async () => {
    const r = await send(e2);
    assert.ok(r.status >= 400 && r.status < 500, 'refused: ' + r.status);
    assert.match((await r.json()).error || '', /Envoi inconnu/);
    assert.equal(e2.UPLOADS.store.has(KEY), false, "the bytes put are taken back");
  });
  await withPostgres({}, async (asked) => {
    const r = await send(env(), "nope");
    assert.equal(r.status, 403);
    assert.equal(asked.length, 0);
  });
});
