// Mara hors ligne — the copy of the app a business keeps on its phone.
//
// Registered only when a business owner chose « Utiliser Mara sans
// connexion » and pressed « Télécharger pour hors ligne » (offline_web.dart).
// A shopper never has it: the street is read online.
//
// Network first, always. The worker this app shipped before served the
// whole old app from cache and updated in the background, so phones ran
// week-old bundles while deploys went green (see flutter_service_worker.js,
// its self-destruct). This one only answers from its copy when the network
// does not: online, every file is the deployed one and the copy is refreshed
// as it goes; offline, the last copy opens the app.
//
// Only this site's own files are kept. Supabase, the photo Worker and every
// other origin pass through untouched: data is the app's business (its
// local database and outbox), not this worker's.
const CACHE = 'mara-offline-v1';

// One worker per scope: this one replaces push_sw.js when it is registered,
// so it carries the push handlers too (alerts on new orders keep working).
importScripts('push_sw.js');

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const key of await caches.keys()) {
      if (key !== CACHE) await caches.delete(key);
    }
    await self.clients.claim();
  })());
});

// « Télécharger pour hors ligne »: the page sends the files it has loaded
// (and the ones it will need), the worker fetches and keeps each, and says
// how far it got.
self.addEventListener('message', (event) => {
  const data = event.data || {};
  const port = event.ports && event.ports[0];
  if (data.type === 'precache' && Array.isArray(data.urls)) {
    event.waitUntil((async () => {
      const cache = await caches.open(CACHE);
      let done = 0;
      let failed = 0;
      for (const url of data.urls) {
        try {
          const response = await fetch(url, { cache: 'no-cache' });
          if (response.ok) {
            await cache.put(url, response.clone());
          } else {
            failed++;
          }
        } catch (_) {
          failed++;
        }
        done++;
        if (port) port.postMessage({ type: 'progress', done, total: data.urls.length });
      }
      if (port) port.postMessage({ type: 'done', done, failed });
    })());
  } else if (data.type === 'forget') {
    event.waitUntil((async () => {
      await caches.delete(CACHE);
      await self.registration.unregister();
      if (port) port.postMessage({ type: 'done', done: 0, failed: 0 });
    })());
  }
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;
  // The version file is how the app learns a new build exists: never kept.
  if (url.pathname === '/version.json') return;

  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    try {
      const response = await fetch(request);
      if (response.ok && response.type === 'basic') {
        // A page address is the one app shell: kept under « / ».
        const key = request.mode === 'navigate' ? '/' : request;
        cache.put(key, response.clone());
      }
      return response;
    } catch (error) {
      const kept = await cache.match(request.mode === 'navigate' ? '/' : request, { ignoreSearch: true });
      if (kept) return kept;
      throw error;
    }
  })());
});
