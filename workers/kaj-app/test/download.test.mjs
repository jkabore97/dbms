// /telecharger (src/download.js): one link that opens the phone's own
// store, and a page with both for anything else.
//
//   node --test workers/kaj-app/test/*.test.mjs

import assert from "node:assert/strict";
import { afterEach, test } from "node:test";

import site from "../src/index.js";
import { APP_STORE_URL, PLAY_URL, forgetStoreLinks, linksFrom, phoneOf } from "../src/download.js";

const env = {
  SUPABASE_URL: "https://db.example.supabase.co",
  SUPABASE_PUBLISHABLE_KEY: "sb_publishable_test",
  ASSETS: { async fetch() { return new Response("<html></html>", { headers: { "Content-Type": "text/html" } }); } },
};
const realFetch = globalThis.fetch;
const asked = [];

function supabase(answer) {
  globalThis.fetch = async (url) => {
    asked.push(String(url));
    if (answer instanceof Error) throw answer;
    return new Response(JSON.stringify(answer), { headers: { "Content-Type": "application/json" } });
  };
}

afterEach(() => {
  globalThis.fetch = realFetch;
  asked.length = 0;
  forgetStoreLinks();
});

const ANDROID = "Mozilla/5.0 (Linux; Android 14; SM-A155F) AppleWebKit/537.36 Chrome/130 Mobile Safari/537.36";
const IPHONE = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 Version/18.1 Mobile/15E148 Safari/604.1";
const IPAD = "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148";
const DESKTOP = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130 Safari/537.36";

const get = (path, ua) => site.fetch(new Request(`https://marakaj.com${path}`, { headers: { "User-Agent": ua } }), env);

test("phoneOf tells Android from iPhone/iPad from the rest", () => {
  assert.equal(phoneOf(ANDROID), "android");
  assert.equal(phoneOf(IPHONE), "ios");
  assert.equal(phoneOf(IPAD), "ios");
  assert.equal(phoneOf(DESKTOP), null);
  assert.equal(phoneOf(undefined), null);
});

test("an Android phone goes to Google Play", async () => {
  supabase({ android: PLAY_URL, android_store: true, ios: null });
  const r = await get("/telecharger", ANDROID);
  assert.equal(r.status, 302);
  assert.equal(r.headers.get("Location"), PLAY_URL);
  assert.equal(r.headers.get("Cache-Control"), "no-store");
});

test("an iPhone goes to the App Store, the published one while Réglages has none", async () => {
  supabase({ android: PLAY_URL, android_store: true, ios: null });
  const r = await get("/download/", IPHONE);
  assert.equal(r.status, 302);
  assert.equal(r.headers.get("Location"), APP_STORE_URL);
});

test("the App Store address set in Réglages wins", async () => {
  supabase({ android: PLAY_URL, android_store: true, ios: "https://apps.apple.com/bf/app/marakaj/id6821171857" });
  const r = await get("/telecharger", IPHONE);
  assert.equal(r.headers.get("Location"), "https://apps.apple.com/bf/app/marakaj/id6821171857");
});

test("a computer gets a page with both stores and a preview for WhatsApp", async () => {
  supabase({ android: PLAY_URL, android_store: true, ios: null });
  const r = await get("/telecharger", DESKTOP);
  assert.equal(r.status, 200);
  const html = await r.text();
  assert.match(html, /play\.google\.com\/store\/apps\/details\?id=bf\.kaj\.app/);
  assert.match(html, /apps\.apple\.com\/app\/id6821171857/);
  assert.match(html, /og:title/);
});

test("Supabase down: the published listings, never a 500", async () => {
  supabase(new Error("down"));
  const a = await get("/telecharger", ANDROID);
  assert.equal(a.headers.get("Location"), PLAY_URL);
  forgetStoreLinks();
  const i = await get("/telecharger", IPHONE);
  assert.equal(i.headers.get("Location"), APP_STORE_URL);
});

test("only a store's address is followed; the APK is not the store link", () => {
  assert.deepEqual(linksFrom({ android: "https://evil.example/x", android_store: true, ios: "javascript:alert(1)" }),
    { android: PLAY_URL, ios: APP_STORE_URL });
  assert.deepEqual(linksFrom({ android: "https://github.com/x.apk", android_store: false }),
    { android: PLAY_URL, ios: APP_STORE_URL });
  assert.deepEqual(linksFrom(null), { android: PLAY_URL, ios: APP_STORE_URL });
});

test("asked once a minute, not every visit", async () => {
  supabase({ android: PLAY_URL, android_store: true, ios: null });
  await get("/telecharger", ANDROID);
  await get("/telecharger", IPHONE);
  assert.equal(asked.length, 1);
});
