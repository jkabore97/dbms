// How long a phone may keep each file of the site (src/index.js, cacheFor).
//
//   node --test workers/kaj-app/test/*.test.mjs
//
// The assets binding is played by a little map of files; for an address it
// does not have it answers the app's page, as the real one does with
// not_found_handling = "single-page-application".

import assert from "node:assert/strict";
import { test } from "node:test";

import site from "../src/index.js";

const PAGE = "<!DOCTYPE html><html><head><title>Mara</title></head><body></body></html>";
const files = {
  "/index.html": [PAGE, "text/html; charset=utf-8"],
  "/app/0123456789ab/main.dart.js": ["main()", "text/javascript"],
  "/ck/abcdefabcdef/chromium/canvaskit.wasm": ["\0asm", "application/wasm"],
  "/a/fedcba987654/assets/FontManifest.json": ["[]", "application/json"],
  "/mara_sw.js": ["//sw", "text/javascript"],
  "/version.json": ['{"sha":"x"}', "application/json"],
  "/sqlite3.wasm": ["\0asm", "application/wasm"],
};
const env = {
  ASSETS: {
    async fetch(request) {
      const path = new URL(request.url).pathname;
      const [body, type] = files[path] || files["/index.html"];
      return new Response(body, {
        headers: { "Content-Type": type, "Cache-Control": "public, max-age=0, must-revalidate", ETag: '"e"' },
      });
    },
  },
};
const get = (path) => site.fetch(new Request(`https://marakaj.com${path}`), env);

test("a build's own folders are kept a year, untouched", async () => {
  for (const path of [
    "/app/0123456789ab/main.dart.js",
    "/ck/abcdefabcdef/chromium/canvaskit.wasm",
    "/a/fedcba987654/assets/FontManifest.json",
  ]) {
    const r = await get(path);
    assert.equal(r.status, 200, path);
    assert.equal(r.headers.get("Cache-Control"), "public, max-age=31536000, immutable", path);
    assert.equal(r.headers.get("ETag"), '"e"');
    assert.equal(r.headers.get("Content-Type"), files[path][1]);
  }
});

test("a folder of a build no longer deployed is « not found », never the page", async () => {
  const r = await get("/app/999999999999/main.dart.js_1.part.js");
  assert.equal(r.status, 404);
  assert.equal(r.headers.get("Cache-Control"), "no-store");
  assert.notEqual(await r.text(), PAGE);
});

test("the page, the workers and version.json are asked about every time", async () => {
  for (const path of ["/", "/index.html", "/s/tony-pizza/extra", "/vitrines", "/mara_sw.js", "/version.json"]) {
    const r = await get(path);
    assert.equal(r.headers.get("Cache-Control"), "no-cache", path);
  }
});

test("everything else keeps the platform's revalidation", async () => {
  const r = await get("/sqlite3.wasm");
  assert.equal(r.headers.get("Cache-Control"), "public, max-age=0, must-revalidate");
});

test("the old address still sends everyone to marakaj.com", async () => {
  const r = await site.fetch(new Request("https://dbms.kabore-boss.workers.dev/s/x?y=1"), env);
  assert.equal(r.status, 301);
  assert.equal(r.headers.get("Location"), "https://marakaj.com/s/x?y=1");
});

test("a vitrine's page, previewed or not, is asked about every time", async () => {
  // No Supabase configured here: the page goes out with Mara's own tags.
  const r = await get("/s/tony-pizza");
  assert.equal(r.status, 200);
  assert.equal(r.headers.get("Cache-Control"), "no-cache");
});

test("every page and file carries the security headers web filters look for", async () => {
  for (const path of ["/", "/app/0123456789ab/main.dart.js", "/ck/abcdefabcdef/chromium/canvaskit.wasm", "/version.json"]) {
    const r = await get(path);
    assert.equal(r.headers.get("Strict-Transport-Security"), "max-age=31536000", path);
    assert.equal(r.headers.get("X-Content-Type-Options"), "nosniff", path);
    assert.equal(r.headers.get("X-Frame-Options"), "SAMEORIGIN", path);
    assert.equal(r.headers.get("Referrer-Policy"), "strict-origin-when-cross-origin", path);
    assert.match(r.headers.get("Permissions-Policy"), /geolocation=\(self\)/, path);
  }
  // The wasm keeps its own type: with nosniff a wrong one would not load.
  assert.equal((await get("/ck/abcdefabcdef/chromium/canvaskit.wasm")).headers.get("Content-Type"), "application/wasm");
  // A redirect is left as it is.
  const moved = await site.fetch(new Request("https://dbms.kabore-boss.workers.dev/x"), env);
  assert.equal(moved.status, 301);
});
