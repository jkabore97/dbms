// The bare push worker: alerts and nothing else.
//
// Every visitor normally has mara_sw.js at this scope already (index.html
// registers it), and it carries the same push handlers. The app registers
// this one only where no worker holds the scope yet — a browser that
// refused the first — when a person turns alerts on
// (core/notify/push_client_web.dart). The next page load puts mara_sw.js in
// its place; the push subscription belongs to the scope, not the file, so
// it survives the swap. The subscription is saved under the person's
// account (060) and the push Worker (workers/push) sends to it.
//
// It caches nothing and intercepts no fetch.

importScripts("push_handlers.js");

self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()));
