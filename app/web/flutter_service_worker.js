// The self-destructing service worker.
//
// The app used to ship Flutter's offline-first service worker, which serves
// the ENTIRE old app from cache on every reload and updates only in the
// background — so phones kept running week-old bundles while deploys went
// green, and every fix looked unshipped. The build now uses
// --pwa-strategy none, so no new service worker is ever registered.
//
// This file exists for the phones that already installed the old one: their
// browser re-fetches this URL on navigation, sees new bytes, installs this
// in its place — and this one deletes every cache, unregisters itself, and
// reloads the page so the fresh app arrives immediately. After that, the
// browser's ordinary HTTP caching (see _headers) keeps updates instant.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const key of await caches.keys()) {
      await caches.delete(key);
    }
    await self.registration.unregister();
    const clients = await self.clients.matchAll({ type: 'window' });
    for (const client of clients) {
      client.navigate(client.url);
    }
  })());
});
