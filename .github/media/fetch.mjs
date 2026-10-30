// Temporary (Marakaj event templates, Premium): finds free videos and photos on Pixabay
// (Pixabay Content License) in a real browser, downloads them, and writes list.json.
import {chromium} from 'playwright';
import fs from 'fs';
const TOPICS = {
  sahel: [['videos', 'giraffe savanna'], ['videos', 'acacia sunset'], ['photos', 'savanna sunset acacia']],
  lotus: [['videos', 'lotus flower'], ['videos', 'koi pond'], ['photos', 'lotus pond']],
  foret: [['videos', 'forest fog sunlight'], ['videos', 'misty forest'], ['photos', 'forest sunbeams']],
  cerisiers: [['videos', 'cherry blossom'], ['videos', 'sakura petals'], ['photos', 'cherry blossom']],
  tournesols: [['videos', 'sunflower field'], ['videos', 'sunflowers sunset'], ['photos', 'sunflower field']],
  lanternes: [['videos', 'sky lanterns'], ['videos', 'floating lanterns'], ['photos', 'sky lanterns']],
  roseraie: [['videos', 'red rose'], ['videos', 'rose garden'], ['photos', 'roses wedding']],
  desert: [['videos', 'desert dunes'], ['videos', 'camel desert'], ['photos', 'sahara dunes']],
  ocean: [['videos', 'ocean sunset waves'], ['videos', 'palm beach sunset'], ['photos', 'beach sunset palm']],
  champagne: [['videos', 'champagne'], ['videos', 'champagne bubbles'], ['photos', 'champagne glasses']],
  papillons: [['videos', 'butterfly flower'], ['videos', 'butterflies'], ['photos', 'butterfly']],
  hiver: [['videos', 'snow night village'], ['videos', 'snowfall'], ['photos', 'winter snow night']],
  feux: [['videos', 'fireworks'], ['videos', 'fireworks city'], ['photos', 'fireworks']],
  aurore: [['videos', 'aurora borealis'], ['videos', 'northern lights'], ['photos', 'aurora borealis']]
};
const browser = await chromium.launch({channel: 'chrome', headless: true, args: ['--disable-blink-features=AutomationControlled']});
const ctx = await browser.newContext({userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Safari/537.36', locale: 'en-US'});
const page = await ctx.newPage();
fs.mkdirSync('raw', {recursive: true});
const out = {};
async function links(kind, term) {
  const url = `https://pixabay.com/${kind}/search/${encodeURIComponent(term)}/`;
  try {
    const r = await page.goto(url, {waitUntil: 'domcontentloaded', timeout: 60000});
    await page.waitForTimeout(5000);
    const re = kind === 'videos' ? /\/videos\/[a-z0-9-]+-\d+\/?$/ : /\/photos\/[a-z0-9-]+-\d+\/?$/;
    const ls = await page.$$eval('a[href]', (as) => as.map((a) => a.href));
    return {status: r ? r.status() : 0, list: [...new Set(ls.filter((h) => re.test(h)))]};
  } catch (e) { return {status: 'err ' + e, list: []}; }
}
for (const [topic, qs] of Object.entries(TOPICS)) {
  out[topic] = [];
  for (const [kind, term] of qs) {
    const {status, list} = await links(kind, term);
    out[topic].push({kind, term, status, found: list.length});
    let got = 0;
    for (const href of list.slice(0, 8)) {
      if (got >= (kind === 'videos' ? 3 : 3)) break;
      try {
        await page.goto(href, {waitUntil: 'domcontentloaded', timeout: 60000});
        await page.waitForTimeout(2500);
        const html = await page.content();
        const text = await page.evaluate(() => document.body.innerText);
        const title = (await page.title()).replace(/\s*\|.*$/, '');
        let src = null;
        if (kind === 'videos') {
          const all = [...new Set((html.match(/https:\/\/cdn\.pixabay\.com\/video\/[^"'\s]+?\.mp4/g) || []))];
          src = all.find((u) => /_large\.mp4/.test(u)) || all.find((u) => /_medium\.mp4/.test(u)) || all[0] || null;
        } else {
          const all = [...new Set((html.match(/https:\/\/cdn\.pixabay\.com\/photo\/[^"'\s]+?_(1920|1280)\.(jpg|png)/g) || []))];
          src = all.find((u) => /_1920\./.test(u)) || all[0] || null;
        }
        const rec = {topic, kind, term, href, title, src, license: /Content License/i.test(text)};
        if (src) {
          const res = await ctx.request.get(src, {headers: {referer: href}, timeout: 120000});
          if (res.ok()) { const f = `raw/${topic}_${kind[0]}${got}_${href.split('/').filter(Boolean).pop()}.${kind === 'videos' ? 'mp4' : 'jpg'}`; fs.writeFileSync(f, await res.body()); rec.file = f; got++; }
          else rec.status = res.status();
        }
        out[topic].push(rec);
      } catch (e) { out[topic].push({href, error: String(e)}); }
    }
  }
}
fs.writeFileSync('raw/list.json', JSON.stringify(out, null, 1));
await browser.close();
console.log('done');
