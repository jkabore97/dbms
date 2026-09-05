// The push service worker: the only service worker this app registers.
//
// The app runs with --pwa-strategy none on purpose (see
// flutter_service_worker.js for the week-old-bundle story), so this one
// caches nothing and intercepts no fetch. It exists for two events the page
// cannot receive when it is closed: a push arriving, and a tap on the
// notification it showed.
//
// Registered by the app at /push_sw.js (core/orders/push_client_web.dart)
// when a person turns alerts on; the subscription it yields is saved under
// their account (060) and the push Worker (workers/push) sends to it.

self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()));

self.addEventListener("push", (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch {
    data = { body: event.data ? event.data.text() : "" };
  }
  const title = data.title || "Kaj";
  const options = {
    body: data.body || "",
    icon: "/icons/Icon-192.png",
    badge: "/icons/Icon-192.png",
    tag: data.tag,
    renotify: Boolean(data.tag),
    data: { url: data.url || "/" },
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const url = (event.notification.data && event.notification.data.url) || "/";
  event.waitUntil((async () => {
    // An open tab of the app is brought forward and sent to the page;
    // otherwise a new one opens there.
    const tabs = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
    for (const tab of tabs) {
      if ("focus" in tab) {
        await tab.focus();
        if ("navigate" in tab) {
          try { await tab.navigate(url); } catch { /* cross-origin or refused: the focus is enough */ }
        }
        return;
      }
    }
    await self.clients.openWindow(url);
  })());
});
