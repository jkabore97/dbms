// A card's films and songs answered in parts (src/index.js, ranged): an
// iPhone plays no video whose server ignores « Range ».
//
//   node --test workers/kaj-app/test/*.test.mjs

import assert from "node:assert/strict";
import { test } from "node:test";

import site from "../src/index.js";

const FILM = new Uint8Array(1000).map((_, i) => i % 256);
const env = {
  ASSETS: {
    async fetch(request) {
      const path = new URL(request.url).pathname;
      if (path === "/cartes/films/pe-jardin.mp4") return new Response(FILM, { headers: { "Content-Type": "video/mp4" } });
      return new Response("<!DOCTYPE html><html></html>", { headers: { "Content-Type": "text/html" } });
    },
  },
};
const get = (path, headers = {}, method = "GET") => site.fetch(new Request(`https://marakaj.com${path}`, { method, headers }), env);

test("a film asked whole: all of it, and the server says it takes parts", async () => {
  const r = await get("/cartes/films/pe-jardin.mp4");
  assert.equal(r.status, 200);
  assert.equal(r.headers.get("Accept-Ranges"), "bytes");
  assert.equal((await r.arrayBuffer()).byteLength, 1000);
});

test("a film asked in parts: the part, its place in the whole", async () => {
  let r = await get("/cartes/films/pe-jardin.mp4", { Range: "bytes=0-1" });
  assert.equal(r.status, 206);
  assert.equal(r.headers.get("Content-Range"), "bytes 0-1/1000");
  assert.deepEqual([...new Uint8Array(await r.arrayBuffer())], [0, 1]);
  r = await get("/cartes/films/pe-jardin.mp4", { Range: "bytes=990-" });
  assert.equal(r.headers.get("Content-Range"), "bytes 990-999/1000");
  assert.equal(r.headers.get("Content-Length"), "10");
  r = await get("/cartes/films/pe-jardin.mp4", { Range: "bytes=-5" });
  assert.equal(r.headers.get("Content-Range"), "bytes 995-999/1000");
  r = await get("/cartes/films/pe-jardin.mp4", { Range: "bytes=2000-" });
  assert.equal(r.status, 416);
  assert.equal(r.headers.get("Content-Range"), "bytes */1000");
});

test("a film that is not there: « not found », never the app's page", async () => {
  const r = await get("/cartes/films/nope.mp4", { Range: "bytes=0-1" });
  assert.equal(r.status, 404);
});
