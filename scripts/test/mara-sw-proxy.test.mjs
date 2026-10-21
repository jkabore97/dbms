// The phone's service worker (app/web/mara_sw.js) never answers the site's
// Supabase path (/sb/…) from its caches: that is data, not the app.
//
//   node --test scripts/test/*.test.mjs

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('../../app/web/mara_sw.js', import.meta.url), 'utf8')
  .replace('/*MARA_BUILD*/null', JSON.stringify({
    version: 'v1', shell: { '/': 'x' }, dirs: { app: '/app/0123456789ab/' }, files: [],
  }));

function worker() {
  const handlers = {};
  const self = {
    location: { origin: 'https://marakaj.com' },
    addEventListener: (name, fn) => { handlers[name] = fn; },
    clients: {},
    registration: {},
  };
  vm.runInNewContext(source, {
    self, importScripts() {}, URL, Response, Request, Headers, console, caches: { open: async () => ({ match: async () => null, put: async () => {} }) },
    fetch: async () => new Response('x'),
    setTimeout, clearTimeout, Promise,
  });
  return handlers.fetch;
}

function event(url, init = {}) {
  const request = new Request(url, init);
  let answered = false;
  return {
    request,
    respondWith() { answered = true; },
    waitUntil() {},
    get answered() { return answered; },
  };
}

test('/sb/ reads go to the network untouched; the app\'s own files do not', () => {
  const onFetch = worker();
  for (const url of [
    'https://marakaj.com/sb/rest/v1/rpc/storefront_directory',
    'https://marakaj.com/sb/rest/v1/orgs?select=id',
    'https://marakaj.com/sb',
  ]) {
    const e = event(url, { headers: { apikey: 'k' } });
    onFetch(e);
    assert.equal(e.answered, false, url);
  }
  const page = event('https://marakaj.com/brand/og.jpg');
  onFetch(page);
  assert.equal(page.answered, true);
});
