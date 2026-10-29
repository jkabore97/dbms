// Search Pixabay Music in a real browser, keep tracks under the Pixabay Content License with no
// Content ID note, download their mp3s and write list.json. Temporary (welcome-gift promo).
import {chromium} from 'playwright';
import fs from 'fs';
const terms = ['coupe decale', 'coupé décalé', 'ivorian', 'afro club', 'afrobeat dance', 'ndombolo'];
const browser = await chromium.launch({channel: 'chrome', headless: true, args: ['--disable-blink-features=AutomationControlled']});
const ctx = await browser.newContext({userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Safari/537.36', locale: 'fr-FR'});
const page = await ctx.newPage();
fs.mkdirSync('out', {recursive: true});
const seen = new Map();
const log = [];
for (const term of terms) {
  const url = 'https://pixabay.com/music/search/' + encodeURIComponent(term) + '/';
  try {
    const r = await page.goto(url, {waitUntil: 'domcontentloaded', timeout: 60000});
    await page.waitForTimeout(6000);
    const html = await page.content();
    fs.writeFileSync(`out/search_${term.replace(/\W+/g, '_')}.html`, html);
    const links = await page.$$eval('a[href*="/music/"]', (as) => as.map((a) => ({href: a.href, text: a.textContent.trim()})).filter((l) => /\/music\/[a-z-]+-\d+\/?$/.test(l.href)));
    log.push({term, status: r ? r.status() : null, links: links.length});
    for (const l of links.slice(0, 12)) if (!seen.has(l.href)) seen.set(l.href, {term, text: l.text});
  } catch (e) { log.push({term, error: String(e)}); }
}
const tracks = [];
let n = 0;
for (const [href, info] of seen) {
  if (n >= 24) break;
  n++;
  try {
    const r = await page.goto(href, {waitUntil: 'domcontentloaded', timeout: 60000});
    await page.waitForTimeout(3500);
    const text = await page.evaluate(() => document.body.innerText);
    const html = await page.content();
    const mp3 = (html.match(/https:\/\/cdn\.pixabay\.com\/(?:download\/)?audio\/[^"'\s]+?\.mp3/) || [])[0] || null;
    const t = {href, term: info.term, title: (await page.title()).replace(/\s*\|.*$/, ''), contentId: /content id/i.test(text), license: /Pixabay Content License|Licence de contenu Pixabay|Content License/i.test(text), mp3, status: r ? r.status() : null, tags: (text.match(/#?\b(afro|coupe|décalé|decale|ivor|dance|club|african)\w*/gi) || []).slice(0, 12)};
    if (mp3 && !t.contentId) {
      const res = await ctx.request.get(mp3, {headers: {referer: href}});
      if (res.ok()) { const f = `out/${String(tracks.length).padStart(2, '0')}_${href.split('/').filter(Boolean).pop()}.mp3`; fs.writeFileSync(f, await res.body()); t.file = f; }
    }
    tracks.push(t);
  } catch (e) { tracks.push({href, error: String(e)}); }
}
fs.writeFileSync('out/list.json', JSON.stringify({log, tracks}, null, 1));
await browser.close();
console.log(JSON.stringify(log), tracks.filter((t) => t.file).length, 'downloaded');
