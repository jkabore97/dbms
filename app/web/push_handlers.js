// The two events a page cannot receive while it is closed: a push arriving,
// and a tap on the notification it showed. Shared by both workers that can
// hold this site's scope — mara_sw.js (the one every visitor gets, which
// also keeps the app for slow and absent connections) and push_sw.js (the
// bare one the app registers for alerts when no worker is there yet) — so a
// push subscription keeps working whichever of the two is in place.
//
// Only listeners here: no install/activate. Each worker decides for itself
// when it takes over (mara_sw.js waits to be asked; see there).

self.addEventListener("push", (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch {
    data = { body: event.data ? event.data.text() : "" };
  }
  const title = data.title || "Mara";
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
