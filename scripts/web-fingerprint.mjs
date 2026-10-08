#!/usr/bin/env node
// Gives every file of the web build that changes between builds an address
// that never changes: a folder named after its content.
//
//   node scripts/web-fingerprint.mjs app/build/web <BUILD_SHA>
//
// Run by deploy-cloudflare.yml right after `flutter build web`. Flutter
// names its files the same in every build (main.dart.js, canvaskit/…), so a
// browser — or a service worker — can only ever ask « is this still the
// same file? », a round trip per file before the first frame. After this:
//
//   main.dart.js + its deferred parts  →  /app/<hash>/
//   canvaskit/                         →  /ck/<hash>/
//   assets/ (fonts, pictures, sounds)  →  /a/<hash>/assets/
//
// and index.html (the only file that says which folders a build reads, with
// the Flutter loader inlined into it) gets those three folders written in.
// The site Worker serves the folders as immutable for a year
// (workers/kaj-app/src/index.js); a folder whose files did not change keeps
// its name, so a deploy that changed only the app leaves the 1.5 MB engine
// in every phone's cache.
//
// Then mara_sw.js (the service worker, web/mara_sw.js) gets this build
// written into it: its version, the hash of each fixed-name file it keeps,
// the three folders and every file in them. That change to its bytes is
// what makes the browser install the new worker.
//
// Fails loudly, without touching anything, when the build does not have
// the shape this expects — a Flutter upgrade that renamed something must
// stop the deploy, not ship a page that loads nothing.
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readdirSync, readFileSync, renameSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { join, relative, sep } from 'node:path';

const [root, version] = process.argv.slice(2);
if (!root || !version) {
  console.error('usage: web-fingerprint.mjs <build/web> <BUILD_SHA>');
  process.exit(2);
}

const PATHS = '/*MARA_PATHS*/{}';
const VERSION = '/*MARA_VERSION*/""';
const BUILD = '/*MARA_BUILD*/null';
const PRELOAD = '<!--MARA_PRELOAD-->';

// The files that keep their names, kept by the worker per build. index.html
// is the page itself (« / »); the database engine (sqflite_sw.js and
// sqlite3.wasm) is looked up by name by the plugin; the rest is what the
// page and its notifications load by name.
const SHELL = ['/', '/sqflite_sw.js', '/sqlite3.wasm', '/manifest.json', '/favicon.png', '/icons/Icon-192.png'];

function fail(message) {
  console.error(`web-fingerprint: ${message}`);
  process.exit(1);
}

const at = (p) => join(root, p);
const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');

function walk(dir) {
  const out = [];
  for (const name of readdirSync(dir).sort()) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) out.push(...walk(p));
    else out.push(p);
  }
  return out;
}

// One hash for a set of files: their paths and their contents.
function hashOf(files, base) {
  const h = createHash('sha256');
  for (const f of [...files].sort()) {
    h.update(relative(base, f).split(sep).join('/'));
    h.update('\0');
    h.update(sha256(readFileSync(f)));
    h.update('\0');
  }
  return h.digest('hex').slice(0, 12);
}

// ---------------------------------------------------------------- checks

const index = at('index.html');
const worker = at('mara_sw.js');
for (const need of ['index.html', 'main.dart.js', 'canvaskit', 'assets', 'mara_sw.js', ...SHELL.slice(1).map((p) => p.slice(1))]) {
  if (!existsSync(at(need))) fail(`${need} is missing from ${root}`);
}
let html = readFileSync(index, 'utf8');
if (!html.includes(PATHS)) fail(`index.html has no ${PATHS} — already fingerprinted, or web/index.html lost the loader`);
if (!html.includes(VERSION)) fail(`index.html has no ${VERSION}`);
if (!html.includes(PRELOAD)) fail(`index.html has no ${PRELOAD}`);
if (!html.includes('_flutter.buildConfig')) fail('index.html does not carry the Flutter loader inline ({{flutter_bootstrap_js}})');
let sw = readFileSync(worker, 'utf8');
if (!sw.includes(BUILD)) fail(`mara_sw.js has no ${BUILD}`);

// ---------------------------------------------------------------- folders

const appFiles = readdirSync(root)
  .filter((n) => n === 'main.dart.js' || /^main\.dart\.js_\d+\.part\.js$/.test(n) ||
    n === 'main.dart.js.map' || /^main\.dart\.js_\d+\.part\.js\.map$/.test(n))
  .map((n) => at(n));
const hApp = hashOf(appFiles, root);
const hCk = hashOf(walk(at('canvaskit')), at('canvaskit'));
const hA = hashOf(walk(at('assets')), at('assets'));

const dirs = { app: `/app/${hApp}/`, ck: `/ck/${hCk}/`, a: `/a/${hA}/` };

mkdirSync(at(`app/${hApp}`), { recursive: true });
for (const f of appFiles) renameSync(f, at(`app/${hApp}/${relative(root, f)}`));
mkdirSync(at('ck'), { recursive: true });
renameSync(at('canvaskit'), at(`ck/${hCk}`));
mkdirSync(at(`a/${hA}`), { recursive: true });
renameSync(at('assets'), at(`a/${hA}/assets`));
// The loader lives inside index.html now; standalone copies would load
// main.dart.js from an address that no longer exists.
for (const stale of ['flutter_bootstrap.js', 'flutter.js', 'flutter.js.map']) rmSync(at(stale), { force: true });

// ---------------------------------------------------------------- index.html

// The files the engine fetches before its first frame, asked for by the
// page at once (index.html, <!--MARA_PRELOAD-->): the font list and the
// fonts it names.
const preload = ['assets/FontManifest.json', 'assets/fonts/fallback/Roboto-Regular.ttf', 'assets/fonts/MaterialIcons-Regular.otf']
  .filter((f) => existsSync(at(`a/${hA}/${f}`)))
  .map((f) => `<link rel="preload" href="${dirs.a}${f}" as="fetch" crossorigin>`)
  .join('\n  ');

html = html
  .replace(PATHS, JSON.stringify({ entrypointBaseUrl: dirs.app, canvasKitBaseUrl: dirs.ck, assetBase: dirs.a }))
  .replace(VERSION, JSON.stringify(version))
  .replace(PRELOAD, preload);
writeFileSync(index, html);

// ---------------------------------------------------------------- mara_sw.js

const files = [];
for (const key of ['app', 'ck', 'a']) {
  for (const f of walk(at(dirs[key].slice(1, -1)))) {
    const url = '/' + relative(root, f).split(sep).join('/');
    // Debug symbols and source maps are never fetched by a browser.
    if (/\.(symbols|map)$/.test(url)) continue;
    files.push(url);
  }
}
const shell = {};
for (const p of SHELL) shell[p] = sha256(readFileSync(p === '/' ? index : at(p.slice(1))));
sw = sw.replace(BUILD, JSON.stringify({ version, shell, dirs, files }));
writeFileSync(worker, sw);

console.log(`web-fingerprint: build ${version}`);
for (const [k, v] of Object.entries(dirs)) console.log(`  ${k.padEnd(3)} ${v}`);
console.log(`  ${files.length} files under them, ${SHELL.length} kept by name`);
