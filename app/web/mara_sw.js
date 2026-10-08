// Mara's service worker: the app kept on the phone, so that a second visit
// opens at once on a market's connection, and opens at all with none.
//
// The owner asked: « Make sure the app will load easily even the internet
// is bad. » A first visit has to download the engine and the app — about
// three megabytes, twenty seconds on 3G. Every visit after that downloaded
// most of it again, or at the very least asked about every file in turn
// (twenty-five round trips before the first frame). With this worker the
// files already on the phone are used straight away and the network is
// only asked for what is new.
//
// Why this one cannot do what the old one did. The app once shipped
// Flutter's own offline worker, which served a week-old app from its cache
// and fetched the new one behind it; deploys went green and phones kept
// the old bundle (flutter_service_worker.js is the self-destruct that
// removed it). The difference here is in the addresses:
//
//   * At deploy, scripts/web-fingerprint.mjs moves every built file whose
//     content changes from one build to the next into a folder named after
//     its own content — /app/<hash>/ (main.dart.js and its parts),
//     /ck/<hash>/ (the CanvasKit engine), /a/<hash>/ (fonts, pictures,
//     sounds) — and writes into index.html the folders this build reads.
//     A file under such a folder never changes at that address, so it is
//     kept here forever, cache-first, and shared between builds: a deploy
//     that changes only the app downloads only main.dart.js again.
//   * index.html is the one pointer. This worker keeps its own build's
//     index.html (and the few files that keep their names: the database
//     engine, the manifest, the icons) in mara-shell-<build>, and answers
//     every page opening with it. Two builds can never mix: the page this
//     worker serves only ever asks for its own folders.
//   * A deploy changes this file (BUILD below is written by the deploy), so
//     the browser installs the new worker beside the running one. It
//     prepares the new build — the new index.html, and the new copy of
//     each file this browser used of the old one — then waits. It takes
//     over only when a page asks: at the next start, before the app runs
//     (index.html), or on « Recharger » in the update banner. Then the
//     page reloads, from the phone, into the new build.
//
// Business owners who chose « Utiliser Mara sans connexion » get the
// business half kept too (the "precache" message, offline_app_web.dart),
// and each later build keeps it. Data is not this worker's business: the
// app keeps its own (the local database, the outbox, the street's last
// look). Supabase, the photo Worker and every other origin pass straight
// through.
//
// The push handlers are the same file push_sw.js uses, so alerts keep
// working whichever of the two holds the scope.
importScripts('push_handlers.js');

/* Written by scripts/web-fingerprint.mjs at deploy:
 *   { version: <BUILD_SHA>,
 *     shell: { "/": <sha-256 of index.html>, "/sqflite_sw.js": …, … },
 *     dirs:  { app: "/app/<h>/", ck: "/ck/<h>/", a: "/a/<h>/" },
 *     files: [ every file under those three folders ] }
 * Left null in a build that was not prepared (a local `flutter build`):
 * then this worker refuses to install, and index.html never registers it. */
const BUILD = /*MARA_BUILD*/null;

const SHELL = BUILD ? `mara-shell-${BUILD.version}` : 'mara-shell-none';
const FILES = 'mara-files';
const STATIC = 'mara-static';
const META = 'mara-meta';
const FINGERPRINTED = /^\/(app|ck|a)\/[0-9a-f]{12}\/(.+)$/;
const BUILD_FILES = new Set(BUILD ? BUILD.files : []);
// Plain pages the site Worker writes (workers/kaj-app/src/legal.js): read
// from the network when there is one; the app's own copy otherwise.
const LEGAL = new Set(['/confidentialite', '/conditions']);
// Never kept: how the app and the browser learn a new build exists.
const PASS = new Set(['/mara_sw.js', '/push_sw.js', '/push_handlers.js',
  '/flutter_service_worker.js', '/version.json']);

// ---------------------------------------------------------------- install

self.addEventListener('install', (event) => event.waitUntil(install()));

async function install() {
  if (!BUILD) throw new Error('Mara: this worker was not prepared by the deploy.');
  const shell = await caches.open(SHELL);
  const older = (await caches.keys()).filter((k) => k.startsWith('mara-shell-') && k !== SHELL);
  for (const [path, hash] of Object.entries(BUILD.shell)) {
    if (await holds(shell, path, hash)) continue;
    let kept = null;
    for (const name of older) {
      const cache = await caches.open(name);
      if (await holds(cache, path, hash)) { kept = await cache.match(path); break; }
    }
    // A file that is not this build's (a newer deploy landed meanwhile)
    // fails the install: the running build stays, and the browser tries
    // the newer worker on the next visit.
    await shell.put(path, kept || await fetchVerified(path, hash));
  }
  await carryOver();
}

async function holds(cache, path, hash) {
  const hit = await cache.match(path);
  return Boolean(hit && hit.headers.get('x-mara-hash') === hash);
}

async function fetchVerified(path, hash) {
  const response = await fetch(path, { cache: 'no-cache' });
  if (!response.ok) throw new Error(`Mara: ${path} answered ${response.status}`);
  const body = await response.arrayBuffer();
  // The page is known by the build it names: Cloudflare may rewrite an
  // HTML page on its way (e-mail obfuscation, https links), never the
  // build written into it. Every other file, byte for byte.
  const ours = path === '/'
    ? new TextDecoder().decode(body).includes(`var VERSION = ${JSON.stringify(BUILD.version)};`)
    : hex(await crypto.subtle.digest('SHA-256', body)) === hash;
  if (!ours) throw new Error(`Mara: ${path} is not this build's`);
  const headers = new Headers();
  headers.set('content-type', response.headers.get('content-type') || 'application/octet-stream');
  headers.set('x-mara-hash', hash);
  return new Response(body, { status: 200, headers });
}

function hex(buffer) {
  return [...new Uint8Array(buffer)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

// The new build's copy of what this browser used of the previous one: the
// same engine variant, the app (and its business half if it was opened),
// the fonts and pictures — so the first start of the new build needs no
// network either. Everything of the app's folder when this phone keeps
// the business half for offline.
async function carryOver() {
  const files = await caches.open(FILES);
  const have = new Set((await files.keys()).map((r) => new URL(r.url).pathname));
  const offline = await keepsOffline();
  const wanted = new Set();
  let partsUsed = false;
  for (const path of have) {
    const m = path.match(FINGERPRINTED);
    if (!m) continue;
    if (m[1] === 'app' && m[2] !== 'main.dart.js') partsUsed = true;
    const next = BUILD.dirs[m[1]] + m[2];
    if (BUILD_FILES.has(next)) wanted.add(next);
  }
  if (partsUsed || offline) {
    for (const f of BUILD.files) if (f.startsWith(BUILD.dirs.app)) wanted.add(f);
  }
  if (offline) for (const f of offlineFiles(have)) wanted.add(f);
  for (const path of wanted) {
    if (have.has(path)) continue;
    await keep(files, path);
  }
}

async function keep(files, path) {
  const response = await fetch(path);
  if (!usable(response)) throw new Error(`Mara: ${path} answered ${response.status}`);
  await files.put(self.location.origin + path, response);
}

// A fingerprinted address the server no longer has comes back 404 from
// the site Worker; an HTML page in its place is never kept as a script.
function usable(response) {
  return response.ok && response.status === 200 &&
    !(response.headers.get('content-type') || '').startsWith('text/html');
}

// ---------------------------------------------------------------- activate

self.addEventListener('activate', (event) => event.waitUntil(activate()));

async function activate() {
  const meta = await caches.open(META);
  const before = await meta.match('/__mara/build.json');
  const previous = before ? await before.json().catch(() => null) : null;
  // This build's files, and the previous build's: a tab still running the
  // previous build can go on opening its business half from here.
  const keepFiles = new Set(BUILD.files);
  if (previous && previous.version !== BUILD.version && Array.isArray(previous.files)) {
    for (const f of previous.files) keepFiles.add(f);
  }
  await meta.put('/__mara/build.json',
    new Response(JSON.stringify({ version: BUILD.version, files: BUILD.files })));
  for (const name of await caches.keys()) {
    if (name === SHELL || name === FILES || name === STATIC || name === META) continue;
    // Older builds' shells, the copy offline_sw.js kept (mara-offline-v1),
    // anything Flutter's old worker left.
    await caches.delete(name);
  }
  const files = await caches.open(FILES);
  for (const request of await files.keys()) {
    if (!keepFiles.has(new URL(request.url).pathname)) await files.delete(request);
  }
  await self.clients.claim();
}

// ---------------------------------------------------------------- fetch

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (!BUILD || request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;
  // A sound's byte range is the browser's own business with the network.
  if (request.headers.has('range')) return;
  const path = url.pathname;
  if (PASS.has(path)) return;

  if (request.mode === 'navigate') {
    event.respondWith(LEGAL.has(path.replace(/\/+$/, ''))
      ? networkThenShell(request)
      : shellPage(request));
    return;
  }
  if (FINGERPRINTED.test(path)) {
    event.respondWith(fingerprinted(event, path));
    return;
  }
  const shellPath = path === '/index.html' ? '/' : path;
  if (Object.prototype.hasOwnProperty.call(BUILD.shell, shellPath)) {
    event.respondWith(fromShell(request, shellPath));
    return;
  }
  // The rest of this site — the vitrines d'exemple's photos, the brand
  // pictures: shown as last seen, refreshed behind.
  event.respondWith(staleWhileRevalidate(event, request));
});

// Every address of the app is the one page: this build's.
async function shellPage(request) {
  const page = await (await caches.open(SHELL)).match('/');
  return page || fetch(request);
}

async function networkThenShell(request) {
  try {
    return await fetch(request);
  } catch (error) {
    const page = await (await caches.open(SHELL)).match('/');
    if (page) return page;
    throw error;
  }
}

async function fingerprinted(event, path) {
  const files = await caches.open(FILES);
  const key = self.location.origin + path;
  const hit = await files.match(key);
  if (hit) return hit;
  // dart2js asks again with ?dart2jsRetry=n after a failure; the answer
  // is the same file.
  const response = await fetch(key);
  if (usable(response)) event.waitUntil(files.put(key, response.clone()));
  return response;
}

async function fromShell(request, path) {
  const hit = await (await caches.open(SHELL)).match(path);
  return hit || fetch(request);
}

async function staleWhileRevalidate(event, request) {
  const cache = await caches.open(STATIC);
  const hit = await cache.match(request);
  const fresh = fetch(request).then((response) => {
    if (response.ok && response.status === 200 && response.type === 'basic') {
      return cache.put(request, response.clone()).then(() => response);
    }
    return response;
  });
  if (hit) {
    event.waitUntil(fresh.catch(() => {}));
    return hit;
  }
  return fresh;
}

// ---------------------------------------------------------------- messages

self.addEventListener('message', (event) => {
  const data = event.data || {};
  const port = event.ports && event.ports[0];
  if (data.type === 'activate') {
    // A page asked for the prepared build (index.html at start, or
    // « Recharger »); it reloads once this worker holds the scope.
    self.skipWaiting();
  } else if (data.type === 'warm' && Array.isArray(data.urls)) {
    event.waitUntil(warm(data.urls));
  } else if (data.type === 'precache') {
    event.waitUntil(precache(port));
  } else if (data.type === 'status') {
    event.waitUntil(status(port));
  } else if (data.type === 'forget') {
    event.waitUntil(forget(port));
  }
});

// The first visit: the page loaded its files before this worker held the
// scope; it sends their addresses once it has painted, and they are kept
// (from the browser's own cache — nothing is downloaded twice).
async function warm(urls) {
  if (!BUILD) return;
  const files = await caches.open(FILES);
  for (const url of urls) {
    try {
      const u = new URL(url, self.location.origin);
      if (u.origin !== self.location.origin || !BUILD_FILES.has(u.pathname)) continue;
      if (await files.match(self.location.origin + u.pathname)) continue;
      await keep(files, u.pathname);
    } catch (_) {
      // One file that did not come is one file the next visit asks for.
    }
  }
}

async function keepsOffline() {
  const flag = await (await caches.open(META)).match('/__mara/offline');
  return Boolean(flag);
}

// What « Télécharger pour hors ligne » keeps beyond the shell: the whole
// app folder (both halves), the assets, and the engine variant this
// browser runs (the one it already has; both, if it has neither yet).
function offlineFiles(have) {
  const out = BUILD.files.filter((f) =>
    (f.startsWith(BUILD.dirs.app) || f.startsWith(BUILD.dirs.a)) && !f.endsWith('.map'));
  const engines = BUILD.files.filter((f) => f.startsWith(BUILD.dirs.ck) && /canvaskit\.(js|wasm)$/.test(f));
  const variant = (f) => f.slice(BUILD.dirs.ck.length).replace(/canvaskit\.(js|wasm)$/, '');
  const used = new Set();
  for (const path of have) {
    const m = path.match(FINGERPRINTED);
    if (m && m[1] === 'ck' && /canvaskit\.wasm$/.test(m[2])) used.add(m[2].replace(/canvaskit\.wasm$/, ''));
  }
  for (const f of engines) {
    const v = variant(f);
    if (used.size ? used.has(v) : (v === '' || v === 'chromium/')) out.push(f);
  }
  return out;
}

async function precache(port) {
  const say = (message) => { if (port) port.postMessage(message); };
  if (!BUILD) { say({ type: 'done', done: 0, failed: 1 }); return; }
  await (await caches.open(META)).put('/__mara/offline', new Response('1'));
  const files = await caches.open(FILES);
  const have = new Set((await files.keys()).map((r) => new URL(r.url).pathname));
  const list = offlineFiles(have);
  let done = 0;
  let failed = 0;
  for (const path of list) {
    try {
      if (!have.has(path)) await keep(files, path);
    } catch (_) {
      failed++;
    }
    done++;
    say({ type: 'progress', done, total: list.length });
  }
  say({ type: 'done', done, failed });
}

async function status(port) {
  if (!port) return;
  let offline = false;
  if (BUILD && await keepsOffline()) {
    const files = await caches.open(FILES);
    offline = true;
    for (const f of BUILD.files) {
      if (f.startsWith(BUILD.dirs.app) && !f.endsWith('.map') && !(await files.match(self.location.origin + f))) {
        offline = false;
        break;
      }
    }
  }
  port.postMessage({ type: 'status', version: BUILD ? BUILD.version : null, offline });
}

// « Ne plus garder » — everything this worker kept goes, and so does the
// worker; the next page load starts a fresh one that keeps only what that
// visit uses, like any visitor's.
async function forget(port) {
  for (const name of await caches.keys()) {
    if (name.startsWith('mara-')) await caches.delete(name);
  }
  await self.registration.unregister();
  if (port) port.postMessage({ type: 'done', done: 0, failed: 0 });
}
