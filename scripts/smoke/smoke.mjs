// The public pages, opened in a real browser (audit package 7).
//
// "A successful flutter build is not the same as a page that renders" — a
// regression shipped that way once. This serves the built web app, answers
// its Supabase calls from fixtures (no network, no secrets), opens the
// street and one shop's window at phone size, turns on Flutter's semantics
// tree, and checks that the words a shopper should see are there and that
// nothing threw.
//
// Usage:  node scripts/smoke/smoke.mjs app/build/web
// Needs the `playwright` package; CHROME_PATH picks a browser binary.
import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { extname, join, resolve } from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_PATH || 'playwright');

const root = resolve(process.argv[2] || 'app/build/web');
const types = {
  '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.json': 'application/json', '.wasm': 'application/wasm', '.png': 'image/png',
  '.svg': 'image/svg+xml', '.ttf': 'font/ttf', '.otf': 'font/otf',
  '.css': 'text/css', '.ico': 'image/x-icon',
};

const server = createServer(async (req, res) => {
  const path = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  let file = join(root, path);
  try {
    if (!(await stat(file)).isFile()) throw new Error('dir');
  } catch {
    file = join(root, 'index.html'); // the app's own router takes the path
  }
  res.setHeader('content-type', types[extname(file)] || 'application/octet-stream');
  res.end(await readFile(file));
});
await new Promise((ok) => server.listen(0, '127.0.0.1', ok));
const origin = `http://127.0.0.1:${server.address().port}`;

const shop = {
  org_id: '00000000-0000-0000-0000-0000000000aa', name: 'Boutique Témoin',
  slug: 'boutique-temoin', profile: 'retail', blurb: null,
  address: 'Ouagadougou', lat: 12.37, lng: -1.52, distance_km: null,
};
const rpc = {
  storefront_directory: [shop],
  storefront_featured: [],
  storefront_spotlights: [],
  storefront_previews: [{ slug: shop.slug, product_id: 'p1', name: 'Savon de karité', sale_price: 450, photo_key: null }],
  storefront: [{ ...shop, phone: '+22670000000', theme: 'ardoise', currency: 'XOF', wave_merchant: null, style: {} }],
  storefront_products: [
    { id: 'p1', name: 'Savon de karité', sale_price: 450, in_stock: true, photo_key: null, description: null },
    { id: 'p2', name: 'Bissap', sale_price: 150, in_stock: true, photo_key: null, description: null },
  ],
};

const checks = [
  { path: '/', words: ['Les boutiques près de vous', 'Boutique Témoin', 'Savon de karité'] },
  { path: `/s/${shop.slug}`, words: ['Boutique Témoin', 'Savon de karité', 'Bissap'] },
];

const browser = await chromium.launch(
  process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH } : {});
let failed = 0;
for (const check of checks) {
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, locale: 'fr-FR' });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  // Playwright asks the most recently added route first: the catch-all
  // goes in first, the fixtures last.
  const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*' };
  await ctx.route(/^https?:\/\/(?!127\.0\.0\.1)/, (route) => route.abort());
  await ctx.route(/\/(rest|auth|storage|realtime)\/v1\//, (route) =>
    route.fulfill({ status: 200, headers: cors, contentType: 'application/json', body: '[]' }));
  await ctx.route(/\/rest\/v1\/rpc\/([a-z_]+)/, (route) => {
    const name = route.request().url().match(/\/rpc\/([a-z_]+)/)[1];
    route.fulfill({ status: 200, headers: cors, contentType: 'application/json',
      body: JSON.stringify(rpc[name] ?? []) });
  });

  await page.goto(origin + check.path, { waitUntil: 'load', timeout: 60000 });
  await page.waitForSelector('flutter-view, flt-glass-pane', { timeout: 60000 });
  // Flutter draws on a canvas; its semantics tree is what puts the words in
  // the page, and the placeholder button is how a screen reader turns it on.
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  const missing = [];
  for (const words of check.words) {
    try {
      await page.waitForFunction(
        (w) => document.body.innerText.includes(w) ||
          [...document.querySelectorAll('[aria-label]')].some((e) => e.getAttribute('aria-label').includes(w)),
        words, { timeout: 30000 });
    } catch {
      missing.push(words);
    }
  }
  const ok = missing.length === 0 && errors.length === 0;
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${check.path}` +
    (missing.length ? `  missing: ${missing.join(' | ')}` : '') +
    (errors.length ? `  errors: ${errors.join(' | ').slice(0, 300)}` : ''));
  if (!ok) {
    failed++;
    await page.screenshot({ path: `smoke-${check.path === '/' ? 'home' : 'shop'}.png` });
  }
  await ctx.close();
}
await browser.close();
server.close();
process.exit(failed ? 1 : 0);
