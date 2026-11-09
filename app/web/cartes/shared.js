// Shared by the twelve cards: the line icons, the RSVP (kept on this phone),
// the guests' album (the pictures stay in this browser for the demo), the
// countdown, the lightbox, the toast — and the editor: every text can be
// rewritten, every picture replaced and reframed, and the card can be
// turned to another kind of event (the words and the programme follow).
(function () {
  var sprite = '<svg xmlns="http://www.w3.org/2000/svg" style="position:absolute;width:0;height:0" aria-hidden="true">' +
    '<symbol id="i-rings" viewBox="0 0 48 48"><circle cx="18" cy="28" r="11"/><circle cx="30" cy="28" r="11"/><path d="M26 10l-2 4-2-4 2-2z"/></symbol>' +
    '<symbol id="i-glass" viewBox="0 0 48 48"><path d="M15 7h18l-3 15a6 6 0 0 1-12 0z"/><path d="M24 28v11M17 39h14M18 14c4 3 8 3 12 0"/></symbol>' +
    '<symbol id="i-camera" viewBox="0 0 48 48"><rect x="7" y="15" width="34" height="24" rx="2"/><circle cx="24" cy="27" r="7"/><path d="M17 15l3-5h8l3 5M34 20h3"/></symbol>' +
    '<symbol id="i-dinner" viewBox="0 0 48 48"><circle cx="24" cy="26" r="12"/><circle cx="24" cy="26" r="6"/><path d="M7 12v10M10 12v10M8.5 22v14M40 12c-3 2-3 8 0 10v14"/></symbol>' +
    '<symbol id="i-cake" viewBox="0 0 48 48"><path d="M9 41V27h30v14zM13 27v-8h22v8M24 19v-6"/><path d="M24 13c-2-3 2-5 0-8 2 3-2 5 0 8z"/><path d="M13 33c3 3 5-3 8 0s5 3 8 0 5-3 8 0"/></symbol>' +
    '<symbol id="i-party" viewBox="0 0 48 48"><path d="M13 41l8-21 13 13z"/><path d="M27 14l4-4M33 21l5-2M29 9l1-4M39 27l4 2M35 14l2-2"/><circle cx="41" cy="11" r="1.5"/><circle cx="35" cy="34" r="1.5"/></symbol>' +
    '<symbol id="i-car" viewBox="0 0 48 48"><path d="M8 30l5-11h22l5 11v9H8z"/><circle cx="15" cy="39" r="3"/><circle cx="33" cy="39" r="3"/><path d="M8 30h32M13 19l1 11"/></symbol>' +
    '<symbol id="i-pin" viewBox="0 0 48 48"><path d="M24 42S11 29 11 20a13 13 0 0 1 26 0c0 9-13 22-13 22z"/><circle cx="24" cy="20" r="5"/></symbol>' +
    '<symbol id="i-dress" viewBox="0 0 48 48"><path d="M18 7l6 7 6-7M20 14l-3 9 4 2-9 16h24l-9-16 4-2-3-9"/></symbol>' +
    '<symbol id="i-bed" viewBox="0 0 48 48"><path d="M6 37V17M6 28h36v9M42 28v-7H18v7M10 20h7v6h-7z"/></symbol>' +
    '<symbol id="i-cal" viewBox="0 0 48 48"><rect x="8" y="11" width="32" height="29" rx="2"/><path d="M8 19h32M16 7v8M32 7v8"/><circle cx="24" cy="30" r="3"/></symbol>' +
    '<symbol id="i-gift" viewBox="0 0 48 48"><rect x="8" y="19" width="32" height="21"/><path d="M8 19h32v6H8zM24 19v21M24 19c-6 0-10-3-10-7 4 0 10 3 10 7zM24 19c6 0 10-3 10-7-4 0-10 3-10 7z"/></symbol>' +
    '<symbol id="i-up" viewBox="0 0 48 48"><path d="M24 34V14M15 23l9-9 9 9"/><path d="M9 34v6h30v-6"/></symbol>' +
    '<symbol id="i-dove" viewBox="0 0 48 48"><path d="M10 26c6 2 12 0 16-6 2 6 8 8 14 6-2 8-8 12-16 12-3 0-6-1-8-3l-8 4 4-7c-2-2-2-4-2-6z"/><path d="M26 20c2-6 6-10 12-12-2 4-2 8-2 12"/><circle cx="20" cy="22" r="1"/></symbol>' +
    '<symbol id="i-cap" viewBox="0 0 48 48"><path d="M24 12L6 20l18 8 18-8z"/><path d="M14 24v9c0 3 5 6 10 6s10-3 10-6v-9M42 20v12"/><circle cx="42" cy="34" r="2"/></symbol>' +
    '<symbol id="i-mic" viewBox="0 0 48 48"><rect x="18" y="7" width="12" height="22" rx="6"/><path d="M12 24c0 7 5 12 12 12s12-5 12-12M24 36v6M17 42h14"/></symbol>' +
    '<symbol id="i-ribbon" viewBox="0 0 48 48"><path d="M6 20h36v8H6z"/><path d="M20 20l-6 18 6-4 4 4 4-4 6 4-6-18"/><path d="M24 20v8"/></symbol>' +
    '<symbol id="i-candle" viewBox="0 0 48 48"><rect x="19" y="18" width="10" height="22"/><path d="M24 17c-3-3 2-6 0-9 3 3-2 6 0 9z"/><path d="M14 40h20"/></symbol>' +
    '<symbol id="i-baby" viewBox="0 0 48 48"><circle cx="24" cy="18" r="8"/><path d="M12 42c0-8 5-13 12-13s12 5 12 13M20 10c2-3 6-3 8 0M21 18h.1M27 18h.1"/></symbol>' +
    '<symbol id="i-music" viewBox="0 0 48 48"><path d="M18 36V12l20-4v24"/><circle cx="13" cy="36" r="5"/><circle cx="33" cy="32" r="5"/></symbol>' +
    '</svg>';
  document.body.insertAdjacentHTML('afterbegin', sprite);

  var toastEl = document.createElement('div');
  toastEl.className = 'toast';
  document.body.appendChild(toastEl);
  var toastT;
  function toast(msg) {
    toastEl.textContent = msg;
    toastEl.classList.add('on');
    clearTimeout(toastT);
    toastT = setTimeout(function () { toastEl.classList.remove('on'); }, 2400);
  }

  var lb = document.createElement('div');
  lb.className = 'lb';
  lb.innerHTML = '<img alt=""><button type="button">Fermer</button>';
  document.body.appendChild(lb);
  function close() { lb.classList.remove('on'); }
  lb.addEventListener('click', close);
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') close(); });
  function lightbox(src) { lb.querySelector('img').src = src; lb.classList.add('on'); }

  // ------------------------------------------------------------- server
  // On the site (/e/<slug>), the Worker writes the event into window.CARTE:
  // its words come from there, nothing is kept in the browser, the editor
  // bar stays away (the card is edited from Marakaj), and the RSVP goes to
  // the server. Opened on its own (the proposals' page), everything lives
  // in this browser.
  var SERVER = window.CARTE && typeof window.CARTE === 'object' ? window.CARTE : null;
  // The organiser (154): the server said « editor » for the token in the
  // address. The editor bar shows, the draft is saved to the server with
  // that token, and a replaced picture goes to the uploads Worker, which
  // answers with the key the server minted for it.
  var ORGANISER = SERVER && SERVER.editor === true && SERVER.edit ? SERVER : null;
  function picUrl(key) {
    return SERVER && SERVER.uploads && key ? SERVER.uploads + '/v1/public/objects/' + encodeURIComponent(key) : null;
  }
  var OK_TAGS = { B: 1, I: 1, EM: 1, STRONG: 1, SPAN: 1, SUP: 1, SUB: 1, BR: 1, SMALL: 1 };
  // What a text may carry: a few inline tags and their class, nothing else —
  // the words are written into the page as HTML, and they come from people.
  function clean(html) {
    var doc = new DOMParser().parseFromString('<body>' + String(html == null ? '' : html) + '</body>', 'text/html');
    var walk = function (node) {
      Array.prototype.slice.call(node.childNodes).forEach(function (c) {
        if (c.nodeType === 3) return;
        if (c.nodeType !== 1 || !OK_TAGS[c.tagName]) {
          node.replaceChild(doc.createTextNode(c.textContent || ''), c);
          return;
        }
        Array.prototype.slice.call(c.attributes).forEach(function (a) { if (a.name !== 'class') c.removeAttribute(a.name); });
        walk(c);
      });
    };
    walk(doc.body);
    return doc.body.innerHTML;
  }
  if (SERVER) {
    Array.prototype.forEach.call(document.querySelectorAll('.back'), function (b) { b.hidden = true; });
    // With <base href="/cartes/"> an anchor would leave the page: scroll instead.
    document.addEventListener('click', function (e) {
      var a = e.target.closest && e.target.closest('a[href^="#"]');
      if (!a) return;
      var t = document.getElementById(a.getAttribute('href').slice(1));
      if (t) { e.preventDefault(); t.scrollIntoView({ behavior: 'smooth', block: 'start' }); }
    });
  }

  // ---------------------------------------------------------------- draft
  var card = document.querySelector('.card');
  var id = (card && card.getAttribute('data-card')) || location.pathname.split('/').pop().replace('.html', '') || 'carte';
  var KEY = 'carte-' + id;
  var draft = {};
  if (SERVER) {
    draft = SERVER.content && typeof SERVER.content === 'object' ? JSON.parse(JSON.stringify(SERVER.content)) : {};
  } else {
    try { draft = JSON.parse(localStorage.getItem(KEY) || '{}') || {}; } catch (e) { draft = {}; }
  }
  var memoryOnly = false, dirty = false, markDirty = function () {};
  function save() {
    if (ORGANISER) { dirty = true; markDirty(); return; }
    if (SERVER) return;
    try { localStorage.setItem(KEY, JSON.stringify(draft)); }
    catch (e) { if (!memoryOnly) { memoryOnly = true; toast('Trop de photos pour les garder : elles restent pour cette visite'); } }
  }
  // The organiser's choices beyond the words (170), kept like any text:
  // t:hide — what the card leaves out (word, prog, times, rsvp, qr, album,
  // cd), a comma list; t:colors — their own fond,papier,texte,accent;
  // t:plus-N — texts of their own after the word; p:gN — their own photos
  // in a gallery before the answer.
  function hideList() { return String(draft['t:hide'] || '').split(',').map(function (s) { return s.trim(); }).filter(Boolean); }
  function showList() { return String(draft['t:show'] || '').split(',').map(function (s) { return s.trim(); }).filter(Boolean); }
  // Off by default (170d): the guest's card on a fiançailles (dot) card —
  // shown only once the organiser switches it on (t:show).
  function offByDefault(k) { return k === 'qr' && SERVER && SERVER.kind === 'dot'; }
  function off(k) { return hideList().indexOf(k) >= 0 || (offByDefault(k) && showList().indexOf(k) < 0); }
  function setOff(k, on) {
    var l = hideList().filter(function (x) { return x !== k; }), s = showList().filter(function (x) { return x !== k; });
    if (on) l.push(k); else if (offByDefault(k)) s.push(k);
    if (l.length) draft['t:hide'] = l.join(','); else delete draft['t:hide'];
    if (s.length) draft['t:show'] = s.join(','); else delete draft['t:show'];
  }
  function colorsOf() { var m = /^(#[0-9a-f]{6}),(#[0-9a-f]{6}),(#[0-9a-f]{6}),(#[0-9a-f]{6})$/i.exec(String(draft['t:colors'] || '')); return m ? [m[1], m[2], m[3], m[4]] : null; }
  function rgbOf(h) { return [parseInt(h.substr(1, 2), 16), parseInt(h.substr(3, 2), 16), parseInt(h.substr(5, 2), 16)]; }
  function hexOf(c) { return '#' + c.map(function (v) { return ('0' + Math.round(Math.max(0, Math.min(255, v))).toString(16)).slice(-2); }).join(''); }
  function blend(a, b, t) { var x = rgbOf(a), y = rgbOf(b); return hexOf([x[0] + (y[0] - x[0]) * t, x[1] + (y[1] - x[1]) * t, x[2] + (y[2] - x[2]) * t]); }
  function light(h) { var c = rgbOf(h); return (c[0] * 299 + c[1] * 587 + c[2] * 114) / 255000; }
  function numKeys(re) { return Object.keys(draft).map(function (k) { var m = re.exec(k); return m ? +m[1] : 0; }).filter(Boolean).sort(function (a, b) { return a - b; }); }
  var PICS = Math.max.apply(null, [0].concat(numKeys(/^p:g(\d+)$/)));
  var SECTIONS = { word: '[data-role="word-title"]', prog: '[data-prog], [data-role="prog-title"]', infos: 'ul.infos', pics: '.pics', rsvp: 'form.rsvp', album: '.album-box', foot: '.foot' };
  function sectionOf(k) {
    var el = document.querySelector(SECTIONS[k]);
    return el ? (el.closest('section') || el) : null;
  }
  function applyHides() {
    Object.keys(SECTIONS).forEach(function (k) { var s = sectionOf(k); if (s) s.classList.toggle('is-off', off(k)); });
    Array.prototype.forEach.call(document.querySelectorAll('[data-count]'), function (el) { el.classList.toggle('is-off', off('cd')); });
    // the hours off: blanked where the step is a grid (the columns stay put), gone elsewhere
    Array.prototype.forEach.call(document.querySelectorAll('[data-prog] [data-t]'), function (el) {
      var grid = /grid/.test(getComputedStyle(el.parentElement).display);
      el.classList.toggle('is-blank', off('times') && grid); el.classList.toggle('is-off', off('times') && !grid);
    });
    applyItems();
  }
  // ---------------------------------------------------- the lists (170d)
  // The programme and « Bon à savoir » are lists the organiser shapes. A
  // step or an item of the model is taken away by its place in the
  // model's list (t:hide « prog-0 », « infos-2 »): gone for the guests,
  // faded for the organiser. New ones come after them, each with its own
  // id (t:prog-adds / t:infos-adds, « 1,2 ») and keys of its own (pa-1-t,
  // pa-1-b, pa-1-s; ia-1-b, ia-1-p) — the model's words keep their places
  // (x-N, numbered in reading order), whatever is added.
  var LISTS = {
    prog: { sel: '[data-prog]', adds: 't:prog-adds', key: 'pa', fields: [['[data-t]', 't'], ['[data-b]', 'b'], ['[data-s]', 's']], add: '+ Une étape', label: 'Les étapes', none: 'Nouvelle étape' },
    infos: { sel: 'ul.infos', adds: 't:infos-adds', key: 'ia', fields: [['b', 'b'], ['p', 'p']], add: '+ Une info', label: 'Bon à savoir', none: 'Nouvelle info' }
  };
  function addIds(kind) { return String(draft[LISTS[kind].adds] || '').split(',').map(function (s) { return parseInt(s, 10); }).filter(function (n) { return n > 0 && n < 100; }); }
  function setAddIds(kind, ids) { if (ids.length) draft[LISTS[kind].adds] = ids.join(','); else delete draft[LISTS[kind].adds]; }
  // The model's items get their place (data-li) once, before anything is added.
  function markItems() {
    Object.keys(LISTS).forEach(function (kind) {
      var list = document.querySelector(LISTS[kind].sel); if (!list) return;
      var i = 0;
      Array.prototype.forEach.call(list.children, function (li) { if (li.tagName === 'LI' && !li.hasAttribute('data-la')) li.setAttribute('data-li', String(i++)); });
    });
  }
  function addedItem(kind, id) {
    var L = LISTS[kind], list = document.querySelector(L.sel), proto = list && list.querySelector('li[data-li]');
    if (!proto) return null;
    var li = proto.cloneNode(true);
    li.removeAttribute('data-li'); li.setAttribute('data-la', String(id)); li.classList.remove('is-off', 'li-off');
    Array.prototype.forEach.call(li.querySelectorAll('a, button, .copy, [data-copy]'), function (x) { x.parentNode && x.parentNode.removeChild(x); });
    L.fields.forEach(function (f) {
      var el = li.querySelector(f[0]); if (!el) return;
      el.setAttribute('data-edit', L.key + '-' + id + '-' + f[1]); el.removeAttribute('data-x-wrap');
      var k = 't:' + L.key + '-' + id + '-' + f[1];
      el.innerHTML = draft[k] ? clean(draft[k]) : '';
    });
    // the model's other words in the copy (a number « 01 », a note): not this item's
    Array.prototype.forEach.call(li.querySelectorAll('[data-edit^="x-"]'), function (x) {
      x.removeAttribute('data-edit'); x.removeAttribute('contenteditable');
      x.textContent = /^\s*\d+\s*$/.test(x.textContent) ? String(list.querySelectorAll('li').length + 1).padStart(2, '0') : '';
    });
    if (document.body.classList.contains('editing')) Array.prototype.forEach.call(li.querySelectorAll('[data-edit]'), function (x) { x.setAttribute('contenteditable', 'true'); });
    return li;
  }
  function itemTitle(li, kind) {
    var b = li.querySelector(kind === 'prog' ? '[data-b]' : 'b'), t = b ? b.textContent.replace(/\s+/g, ' ').trim() : '';
    return t || LISTS[kind].none;
  }
  // Every list as the draft says: the model's items shown or taken away,
  // the added ones after them, and — in edit mode — a row of chips under
  // the list: each item (tap: take away / put back; × on an added one),
  // and « + Une étape ».
  function applyItems() {
    Object.keys(LISTS).forEach(function (kind) {
      var L = LISTS[kind], list = document.querySelector(L.sel); if (!list) return;
      Array.prototype.forEach.call(list.querySelectorAll('li[data-la]'), function (li) { li.parentNode.removeChild(li); });
      addIds(kind).forEach(function (id) { var li = addedItem(kind, id); if (li) list.appendChild(li); });
      Array.prototype.forEach.call(list.querySelectorAll('li[data-li]'), function (li) {
        var gone = off(kind + '-' + li.getAttribute('data-li'));
        li.classList.toggle('is-off', gone && !EDITABLE); li.classList.toggle('li-off', gone && EDITABLE);
      });
      var old = list.parentNode.querySelector('.li-ed[data-list="' + kind + '"]'); if (old) old.parentNode.removeChild(old);
      if (!EDITABLE) return;
      var ed = document.createElement('div'); ed.className = 'li-ed'; ed.setAttribute('data-list', kind);
      ed.innerHTML = '<span class="li-lab">' + L.label + ' — touchez pour retirer ou remettre :</span>' +
        Array.prototype.map.call(list.querySelectorAll('li[data-li], li[data-la]'), function (li) {
          var la = li.getAttribute('data-la'), shown = !li.classList.contains('li-off');
          return '<button type="button" ' + (la ? 'data-a="' + la + '"' : 'data-i="' + li.getAttribute('data-li') + '" aria-pressed="' + shown + '"') + '>' +
            esc(itemTitle(li, kind)).slice(0, 40) + (la ? ' ×' : shown ? '' : ' (retirée)') + '</button>';
        }).join('') + '<button type="button" class="li-add">' + L.add + '</button>';
      list.parentNode.insertBefore(ed, list.nextSibling);
    });
  }
  // Text sizes (170d): t:sizes « key:L,key:S » — S, L, XL around the
  // model's own size for that text (measured, so a title grows as a title).
  var SIZES = { S: .82, L: 1.22, XL: 1.5 }, STEPS = ['S', 'M', 'L', 'XL'];
  function sizeMap() {
    var m = {};
    String(draft['t:sizes'] || '').split(',').forEach(function (x) { var r = /^([a-z0-9-]{1,40}):(S|L|XL)$/.exec(x.trim()); if (r) m[r[1]] = r[2]; });
    return m;
  }
  function setSize(key, sz) {
    var m = sizeMap(); if (sz && sz !== 'M') m[key] = sz; else delete m[key];
    var l = Object.keys(m).map(function (k) { return k + ':' + m[k]; });
    if (l.length) draft['t:sizes'] = l.join(','); else delete draft['t:sizes'];
  }
  function applySizes() {
    var m = sizeMap();
    Array.prototype.forEach.call(document.querySelectorAll('[data-fs]'), function (el) { el.style.removeProperty('font-size'); el.removeAttribute('data-fs'); });
    Object.keys(m).forEach(function (k) {
      Array.prototype.forEach.call(document.querySelectorAll('[data-edit="' + k + '"]'), function (el) {
        var base = parseFloat(getComputedStyle(el).fontSize) || 16;
        el.style.fontSize = (base * SIZES[m[k]]).toFixed(1) + 'px'; el.setAttribute('data-fs', m[k]);
      });
    });
  }
  function esc(s) { return String(s).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); }
  function plusText(k) { var d = document.createElement('div'); d.innerHTML = clean(draft[k]); return d.textContent.replace(/\s+/g, ' ').trim(); }
  // The organiser's own texts (170c): t:plus-N the words; t:plus-at where
  // each one stands, in reading order — « N@intro » (under the word or the
  // welcome), « N@prog » (under the programme), « N@rsvp » (before the
  // answer). A text written before the list stands under the intro. A place
  // the card does not have, or has hidden, hands its texts to the next one.
  var SPOTS = ['intro', 'prog', 'rsvp'], EFF = {}, AVL = [], EDITABLE = !SERVER || !!ORGANISER;
  function plusList() {
    var seen = {}, out = [];
    String(draft['t:plus-at'] || '').split(',').forEach(function (s) {
      var m = /^(\d{1,3})@(intro|prog|rsvp)$/.exec(s.trim()); if (!m || seen[m[1]]) return;
      seen[m[1]] = 1; out.push({ n: +m[1], at: m[2] });
    });
    numKeys(/^t:plus-(\d+)$/).forEach(function (n) { if (!seen[n] && plusText('t:plus-' + n)) { seen[n] = 1; out.push({ n: n, at: 'intro' }); } });
    return out;
  }
  function setPlusList(l) {
    // kept in reading order: by place (where each one shows now), then as listed
    var R = { intro: 0, prog: 1, rsvp: 2, end: 3 };
    l = l.map(function (e, i) { return { e: e, i: i, r: R[EFF[e.n] || e.at] }; }).sort(function (a, b) { return a.r - b.r || a.i - b.i; }).map(function (x) { return x.e; });
    if (l.length) draft['t:plus-at'] = l.map(function (e) { return e.n + '@' + e.at; }).join(','); else delete draft['t:plus-at'];
  }
  // A paragraph of the card's own to dress a new text like: a body
  // paragraph, not a title, not an eyebrow.
  function bodyParas(root) {
    return Array.prototype.filter.call(root.querySelectorAll('p'), function (x) {
      return !x.closest('.slot') && !x.hasAttribute('data-role') && !x.classList.contains('eyebrow') && !x.classList.contains('plus');
    });
  }
  function spotOf(a) {
    var s, l, like, f;
    if (a === 'intro') {
      var w = document.querySelector('[data-role="word-title"]');
      s = (w && w.closest('section')) || document.querySelector('section.word, section.welcome');
      if (!s || s.classList.contains('is-off')) return null;
      var paras = bodyParas(s), blocks = paras.concat(Array.prototype.slice.call(s.querySelectorAll('blockquote')));
      // after the last long paragraph — before a short closing (« Avec amour, ») and the signature
      var long = blocks.filter(function (x) { return x.textContent.trim().length > 30; });
      var last = (long.length ? long : blocks).sort(function (x, y) { return x.compareDocumentPosition(y) & 4 ? -1 : 1; }).pop();
      if (!last) return { parent: s, before: null, like: paras[0] || null };
      return { parent: last.parentNode, before: last.nextSibling, like: paras[0] || null };
    }
    if (a === 'prog') {
      l = document.querySelector('[data-prog]') || document.querySelector('#programme .moments');
      if (!l || off('prog') || (l.closest('section') && l.closest('section').classList.contains('is-off'))) return null;
      like = bodyParas(l.closest('section') || l.parentNode)[0] || null;
      var chips = l.parentNode.querySelector(':scope > .li-ed[data-list="prog"]');
      return { parent: l.parentNode, before: chips ? chips.nextSibling : l.nextSibling, like: like };
    }
    if (a === 'rsvp') {
      f = document.querySelector('form.rsvp');
      if (!f || off('rsvp') || (f.closest('section') && f.closest('section').classList.contains('is-off'))) return null;
      var at = f.previousElementSibling && f.previousElementSibling.classList.contains('tickets') ? f.previousElementSibling : f;
      like = document.querySelector('[data-role="rsvp-lead"]');
      return { parent: at.parentNode, before: at, like: like && like.tagName === 'P' ? like : null };
    }
    var foot = document.querySelector('.foot');
    return foot && foot.parentNode ? { parent: foot.parentNode, before: foot, like: null } : { parent: card || document.body, before: null, like: null };
  }
  function makePlus(e, like) {
    var p = like ? like.cloneNode(false) : document.createElement('p');
    ['id', 'data-role', 'contenteditable', 'data-x-wrap'].forEach(function (x) { p.removeAttribute(x); });
    if (!like) p.className = 'lead';
    p.setAttribute('data-edit', 'plus-' + e.n); p.classList.add('plus');
    p.innerHTML = draft['t:plus-' + e.n] ? clean(draft['t:plus-' + e.n]) : '';
    if (document.body.classList.contains('editing')) p.setAttribute('contenteditable', 'true');
    return p;
  }
  function moveBarEl(e, up, down) {
    var d = document.createElement('div'); d.className = 'xmove'; d.setAttribute('data-pn', String(e.n));
    d.innerHTML = '<button type="button" data-pm="up"' + (up ? '' : ' disabled') + '>↑ Monter</button>' +
      '<button type="button" data-pm="down"' + (down ? '' : ' disabled') + '>↓ Descendre</button><button type="button" data-pm="del">Supprimer</button>';
    return d;
  }
  // Every added text in its place, in its order; under each, for the
  // organiser, up, down (through the places, top to bottom), take it away.
  function placePlus() {
    Array.prototype.forEach.call(document.querySelectorAll('[data-edit^="plus-"], .xmove'), function (el) { if (el.parentNode) el.parentNode.removeChild(el); });
    var spots = {}, groups = { intro: [], prog: [], rsvp: [], end: [] };
    var FALL = { intro: ['intro', 'prog', 'rsvp'], prog: ['prog', 'intro', 'rsvp'], rsvp: ['rsvp', 'prog', 'intro'] };
    SPOTS.forEach(function (a) { spots[a] = spotOf(a); });
    EFF = {}; AVL = SPOTS.filter(function (a) { return spots[a]; }); if (!AVL.length) AVL = ['end'];
    plusList().filter(function (e) { return EDITABLE || plusText('t:plus-' + e.n); }).forEach(function (e) {
      var g = FALL[e.at].filter(function (a) { return spots[a]; })[0] || 'end';
      EFF[e.n] = g; groups[g].push(e);
    });
    if (groups.end.length) spots.end = spotOf('end');
    ['intro', 'prog', 'rsvp', 'end'].forEach(function (g) {
      var sp = spots[g], pi = AVL.indexOf(g);
      groups[g].forEach(function (e, gi) {
        sp.parent.insertBefore(makePlus(e, sp.like), sp.before);
        if (EDITABLE) sp.parent.insertBefore(moveBarEl(e, gi > 0 || pi > 0, gi < groups[g].length - 1 || pi < AVL.length - 1), sp.before);
      });
    });
  }
  function movePlus(n, dir) {
    var l = plusList(), i = -1, j = -1, k;
    l.forEach(function (x, m) { if (x.n === n) i = m; });
    if (i < 0) return;
    var e = l[i], cur = EFF[n] || e.at;
    if (dir < 0) { for (k = i - 1; k >= 0; k--) if ((EFF[l[k].n] || l[k].at) === cur) { j = k; break; } }
    else { for (k = i + 1; k < l.length; k++) if ((EFF[l[k].n] || l[k].at) === cur) { j = k; break; } }
    if (j >= 0) { l[i] = l[j]; l[j] = e; }
    else {
      var si = AVL.indexOf(cur) + dir; if (si < 0 || si >= AVL.length) return;
      var dest = AVL[si], first = -1, last = -1; e.at = dest; EFF[n] = dest; l.splice(i, 1);
      l.forEach(function (x, m) { if ((EFF[x.n] || x.at) === dest) { if (first < 0) first = m; last = m; } });
      // going down, it becomes the first of the next place; going up, the last of the one before
      l.splice(dir > 0 ? (first < 0 ? l.length : first) : (last < 0 ? l.length : last + 1), 0, e);
    }
    setPlusList(l); placePlus(); save();
    var p = document.querySelector('[data-edit="plus-' + n + '"]');
    if (p) { p.scrollIntoView({ behavior: 'smooth', block: 'center' }); p.classList.remove('xflash'); void p.offsetWidth; p.classList.add('xflash'); }
  }
  // The gallery: before the answer, one tile a picture.
  function gallery() {
    var g = document.querySelector('.xpics');
    if (!g) {
      var f = document.querySelector('form.rsvp'), fs = f && (f.closest('section') || f);
      if (!fs || !fs.parentNode) return null;
      g = document.createElement('section'); g.className = 'xpics'; g.innerHTML = '<div class="grid"></div>';
      fs.parentNode.insertBefore(g, fs);
    }
    return g.querySelector('.grid');
  }
  function picSlot(n) {
    var grid = gallery(); if (!grid) return null;
    var s = document.createElement('div'); s.className = 'slot'; s.setAttribute('data-pic', 'g' + n);
    s.innerHTML = '<div class="tag"><svg><use href="#i-camera"/></svg>Votre photo</div>';
    grid.appendChild(s);
    return s;
  }

  // ------------------------------------------------------------- presets
  // What changes when the card is turned to another kind of event: the
  // words around the names, and the programme. The names, the date, the
  // place and the message stay the person's own.
  var PRESETS = {
    mariage: { label: 'Mariage', kicker: 'Nous nous marions', sub: 'se marient !', 'word-title': 'Notre jour', 'prog-title': 'Le jour J', 'prog-intro': 'Rendez-vous dès 14 h 30. La cérémonie commence à 15 h.', 'rsvp-title': 'RSVP', 'rsvp-lead': 'Dites-nous si vous pouvez être des nôtres.', 'album-title': 'Vos photos du jour', 'album-lead': 'Vous avez pris une belle photo pendant la fête ? Ajoutez-la ici : les mariés la verront, et tout le monde la retrouvera dans l’album.',
      items: [['15 H', 'rings', 'Cérémonie', 'Sous la tonnelle'], ['16 H 30', 'glass', 'Cocktail', 'Jus frais et bouchées'], ['18 H', 'camera', 'Photos', 'Avec chaque famille'], ['19 H 30', 'dinner', 'Dîner', 'Tables sous les lumières'], ['21 H', 'cake', 'Gâteau', 'Et la première danse'], ['22 H', 'party', 'Soirée', 'Jusqu’au bout de la nuit']] },
    dot: { label: 'Fiançailles · dot', kicker: 'Cérémonie de dot', sub: 'unissent leurs familles', 'word-title': 'Un mot des deux familles', 'prog-title': 'Le déroulement', 'prog-intro': 'Les familles sont accueillies dès 9 h 30.', 'rsvp-title': 'Vous venez ?', 'rsvp-lead': 'Dites-nous si vous serez des nôtres.', 'album-title': 'Vos photos de la cérémonie', 'album-lead': 'Ajoutez les photos que vous prenez : les deux familles les retrouveront dans l’album.',
      items: [['10 H', 'pin', 'Accueil des familles', 'Sous le hangar'], ['11 H', 'gift', 'Présentation de la dot', 'Colas, pagnes, bijoux'], ['12 H 30', 'rings', 'Bénédictions', 'Des anciens'], ['13 H 30', 'dinner', 'Repas', 'Riz gras, poulet, tô'], ['16 H', 'party', 'Danses', 'Jusqu’au soir']] },
    anniversaire: { label: 'Anniversaire', kicker: 'Anniversaire', sub: 'fête ses 30 ans', 'word-title': 'Un mot', 'prog-title': 'La soirée', 'prog-intro': 'Les portes ouvrent à 19 h.', 'rsvp-title': 'Vous venez ?', 'rsvp-lead': 'Dites-moi si vous serez là, pour le gâteau.', 'album-title': 'Vos photos de la soirée', 'album-lead': 'Ajoutez vos photos de la fête : elles iront dans l’album de la soirée.',
      items: [['19 H', 'glass', 'Accueil', 'Un verre pour commencer'], ['20 H 30', 'dinner', 'Dîner', 'Buffet'], ['22 H', 'cake', 'Gâteau', 'Les bougies'], ['22 H 30', 'party', 'DJ', 'Jusqu’à 2 h']] },
    bapteme: { label: 'Baptême', kicker: 'Baptême', sub: 'est baptisé', 'word-title': 'Un mot des parents', 'prog-title': 'La journée', 'prog-intro': 'La cérémonie commence à 10 h.', 'rsvp-title': 'Vous venez ?', 'rsvp-lead': 'Dites-nous si vous serez là.', 'album-title': 'Vos photos du jour', 'album-lead': 'Ajoutez vos photos : elles iront dans l’album de la famille.',
      items: [['10 H', 'dove', 'Cérémonie', 'À l’église'], ['11 H 30', 'camera', 'Photos', 'Sur le parvis'], ['12 H 30', 'dinner', 'Déjeuner', 'À la maison'], ['15 H', 'cake', 'Gâteau', 'Et les cadeaux']] },
    naissance: { label: 'Naissance · dénomination', kicker: 'Dénomination', sub: 'est arrivée', 'word-title': 'Un mot des parents', 'prog-title': 'La cérémonie', 'prog-intro': 'Le septième jour, dès 9 h.', 'rsvp-title': 'Vous venez ?', 'rsvp-lead': 'Dites-nous si vous serez là.', 'album-title': 'Vos photos', 'album-lead': 'Ajoutez vos photos : elles iront dans l’album du bébé.',
      items: [['9 H', 'baby', 'Cérémonie', 'Le nom est donné'], ['10 H', 'dove', 'Bénédictions', 'Des anciens'], ['12 H', 'dinner', 'Repas', 'Pour tous'], ['14 H', 'gift', 'Cadeaux', 'Et les photos']] },
    diplome: { label: 'Remise de diplômes', kicker: 'Remise de diplômes', sub: 'Promotion 2027', 'word-title': 'Un mot', 'prog-title': 'La cérémonie', 'prog-intro': 'Les familles sont attendues dès 8 h 30.', 'rsvp-title': 'Inscription', 'rsvp-lead': 'Confirmez votre présence et le nombre de places.', 'album-title': 'Vos photos', 'album-lead': 'Ajoutez vos photos de la cérémonie : elles iront dans l’album de la promotion.',
      items: [['9 H', 'cap', 'Remise des diplômes', 'Amphithéâtre'], ['11 H', 'mic', 'Discours', 'Major et parrain'], ['12 H', 'camera', 'Photos', 'Par filière'], ['13 H', 'glass', 'Réception', 'Dans le jardin']] },
    gala: { label: 'Soirée · gala', kicker: 'Soirée', sub: 'vous invite', 'word-title': 'Le mot de la direction', 'prog-title': 'Le programme', 'prog-intro': 'Accueil à partir de 18 h 30.', 'rsvp-title': 'Inscription', 'rsvp-lead': 'Confirmez votre participation.', 'album-title': 'Photos de la soirée', 'album-lead': 'Ajoutez vos photos : elles iront dans l’album de la soirée.',
      items: [['18 H 30', 'glass', 'Accueil', 'Cocktail'], ['19 H 30', 'mic', 'Allocutions', 'Dix minutes chacune'], ['20 H 30', 'dinner', 'Dîner', 'Placé'], ['22 H', 'music', 'Concert', 'Sur la terrasse'], ['23 H', 'party', 'Soirée', 'Jusqu’à 1 h']] },
    inauguration: { label: 'Inauguration', kicker: 'Inauguration', sub: 'ouvre ses portes', 'word-title': 'Un mot', 'prog-title': 'Le programme', 'prog-intro': 'Rendez-vous devant l’entrée dès 9 h 45.', 'rsvp-title': 'Inscription', 'rsvp-lead': 'Confirmez votre venue.', 'album-title': 'Photos de l’inauguration', 'album-lead': 'Ajoutez vos photos : elles iront dans l’album.',
      items: [['10 H', 'ribbon', 'Coupure du ruban', 'Devant l’entrée'], ['10 H 30', 'mic', 'Discours', 'Dans la cour'], ['11 H', 'pin', 'Visite', 'Guidée'], ['12 H', 'glass', 'Cocktail', 'Sur la terrasse']] },
    concert: { label: 'Concert · spectacle', kicker: 'En concert', sub: 'en live', 'word-title': 'Le mot de l’artiste', 'prog-title': 'La soirée', 'prog-intro': 'Ouverture des portes à 19 h.', 'rsvp-title': 'Réservation', 'rsvp-lead': 'Réservez votre place.', 'album-title': 'Photos du concert', 'album-lead': 'Ajoutez vos photos du concert : elles iront dans l’album de la soirée.',
      items: [['19 H', 'pin', 'Ouverture des portes', 'Placement libre'], ['20 H', 'mic', 'Première partie', 'Pour chauffer la salle'], ['21 H', 'music', 'Concert', 'Le grand moment'], ['23 H', 'party', 'After', 'Avec le DJ']] },
    culture: { label: 'Festival · événement culturel', kicker: 'Festival', sub: 'vous attend', 'word-title': 'Le mot des organisateurs', 'prog-title': 'Le programme', 'prog-intro': 'Ouverture du site à 10 h.', 'rsvp-title': 'Réservation', 'rsvp-lead': 'Réservez votre place.', 'album-title': 'Photos du festival', 'album-lead': 'Ajoutez vos photos : elles iront dans l’album du festival.',
      items: [['10 H', 'pin', 'Ouverture', 'Le village du festival'], ['11 H', 'camera', 'Expositions', 'Artistes et artisans'], ['15 H', 'mic', 'Spectacles', 'Contes, danse, théâtre'], ['20 H', 'music', 'Concerts', 'Sur la grande scène']] },
    conference: { label: 'Conférence · séminaire', kicker: 'Conférence', sub: 'vous invite', 'word-title': 'Le mot des organisateurs', 'prog-title': 'Le programme', 'prog-intro': 'Accueil des participants dès 8 h 30.', 'rsvp-title': 'Inscription', 'rsvp-lead': 'Inscrivez-vous : les places sont limitées.', 'album-title': 'Photos de la journée', 'album-lead': 'Ajoutez vos photos : elles iront dans l’album de la conférence.',
      items: [['8 H 30', 'glass', 'Accueil', 'Badges et café'], ['9 H', 'mic', 'Interventions', 'À la tribune'], ['12 H 30', 'dinner', 'Déjeuner', 'Sur place'], ['14 H', 'pin', 'Ateliers', 'En petits groupes']] },
    retraite: { label: 'Départ à la retraite', kicker: 'Départ à la retraite', sub: 'tourne une page', 'word-title': 'Un mot', 'prog-title': 'La soirée', 'prog-intro': 'Accueil dès 18 h.', 'rsvp-title': 'Vous venez ?', 'rsvp-lead': 'Dites-nous si vous serez là.', 'album-title': 'Vos photos', 'album-lead': 'Ajoutez vos photos, et vos souvenirs.',
      items: [['18 H', 'glass', 'Accueil', 'Un verre'], ['19 H', 'mic', 'Hommages', 'Des collègues'], ['20 H', 'dinner', 'Dîner', 'Ensemble'], ['22 H', 'party', 'Soirée', 'Musique']] },
    hommage: { label: 'Hommage', kicker: 'À la mémoire de', sub: 'nous a quittés', 'word-title': 'Un mot de la famille', 'prog-title': 'Les cérémonies', 'prog-intro': 'La famille vous accueille dès 7 h 30.', 'rsvp-title': 'Témoignages', 'rsvp-lead': 'Laissez un mot à la famille.', 'album-title': 'Souvenirs', 'album-lead': 'Partagez vos photos avec la famille.',
      items: [['8 H', 'candle', 'Levée du corps', 'À la morgue'], ['10 H', 'dove', 'Messe', 'À l’église'], ['12 H', 'pin', 'Inhumation', 'Au cimetière'], ['14 H', 'dinner', 'Retour', 'À la maison familiale']] }
  };

  function setText(root, sel, html) {
    var el = root.querySelector(sel);
    if (el && html != null) el.innerHTML = html;
  }
  function applyPreset(type, silent) {
    var p = PRESETS[type];
    if (!p) return;
    ['kicker', 'sub', 'word-title', 'prog-title', 'prog-intro', 'rsvp-title', 'rsvp-lead', 'album-title', 'album-lead'].forEach(function (role) {
      var el = document.querySelector('[data-role="' + role + '"]');
      if (el && p[role] != null) {
        el.innerHTML = p[role];
        if (el.getAttribute('data-edit')) delete draft['t:' + el.getAttribute('data-edit')];
      }
    });
    var list = document.querySelector('[data-prog]');
    if (list) {
      var proto = list.getAttribute('data-proto') ? null : list.querySelector('li');
      if (proto) {
        var tpl = proto.cloneNode(true);
        list.innerHTML = '';
        p.items.forEach(function (it) {
          var li = tpl.cloneNode(true);
          var hasT = !!li.querySelector('[data-t]');
          setText(li, '[data-t]', it[0]);
          var use = li.querySelector('use');
          if (use) use.setAttribute('href', '#i-' + it[1]);
          setText(li, '[data-b]', it[2]);
          // A card with no time of its own puts it before the detail.
          setText(li, '[data-s]', hasT ? it[3] : it[0] + ' · ' + it[3]);
          list.appendChild(li);
        });
      }
    }
    draft.type = type;
    if (!silent) {
      // Another type rewrote the words: the organiser's own words written
      // over the old ones (x-…) no longer sit where they were.
      Object.keys(draft).forEach(function (k) { if (k.indexOf('t:x-') === 0) delete draft[k]; });
      // the programme was drawn anew: the steps taken away were the old type's
      hideList().forEach(function (k) { if (/^prog-\d+$/.test(k)) setOff(k, false); });
      Array.prototype.forEach.call(document.querySelectorAll('[data-prog] li'), function (li) { li.removeAttribute('data-li'); li.classList.remove('is-off', 'li-off'); });
      markAll(); markItems(); applyHides(); placePlus(); applySizes();
      if (document.body.classList.contains('editing')) editables().forEach(function (el) { el.setAttribute('contenteditable', 'true'); });
      save(); toast('Carte réglée pour : ' + p.label);
    }
  }

  // Every word of the card is the organiser's to write (159c): the cards
  // marked only their names and a few headlines; the programme, « Bon à
  // savoir », the section titles, the footer stayed as the model wrote
  // them. Each text the card shows, beyond what is marked already, gets a
  // key by its place on the page (x-1, x-2, … in reading order, the same
  // at every opening for the same type) — kept as t:x-N like any other.
  // Not the links and buttons (they act), not the form, the album, the
  // pictures, the countdown.
  var SKIP = 'a, button, label, select, option, textarea, input, form, svg, script, style, .edbar, .album-box, .toast, .li-ed, .xmove, [data-count], [data-pic], [data-slot], [data-edit]';
  function markAll() {
    Array.prototype.forEach.call(document.querySelectorAll('[data-edit^="x-"]'), function (el) {
      if (el.hasAttribute('data-x-wrap')) { el.replaceWith(document.createTextNode(el.textContent)); return; }
      el.removeAttribute('data-edit'); el.removeAttribute('contenteditable');
    });
    var n = 0, root = document.querySelector('.card') || document.body;
    (function walk(el) {
      Array.prototype.forEach.call(el.children, function (c) {
        if (c.matches(SKIP)) return;
        var own = Array.prototype.some.call(c.childNodes, function (t) { return t.nodeType === 3 && t.textContent.trim(); });
        if (!own) { walk(c); return; }
        if (!c.querySelector(SKIP)) { c.setAttribute('data-edit', 'x-' + (++n)); return; }
        // Text beside a link or a marked word: each run of it on its own.
        Array.prototype.slice.call(c.childNodes).forEach(function (t) {
          if (t.nodeType !== 3 || !t.textContent.trim()) return;
          var span = document.createElement('span');
          span.setAttribute('data-edit', 'x-' + (++n)); span.setAttribute('data-x-wrap', '');
          span.textContent = t.textContent; t.replaceWith(span);
        });
        walk(c);
      });
    })(root);
  }
  function editables() { return Array.prototype.slice.call(document.querySelectorAll('[data-edit]')); }

  // ------------------------------------------------- what the draft says
  if (draft.type) applyPreset(draft.type, true);
  markAll();
  markItems();

  // ------------------------------------------ colours and writing (159c)
  // Like the animated designs: the model's own, or one of these, kept as
  // pal (0 = the model's) and font ('' = the model's) in the card's content.
  // Every card draws with the same variables, so each set fits all twelve.
  var PALS = [
    ['Celle du modèle'],
    ['Ivoire et noir', '#141414', '#f6f3ec', '#151515', '#cfc9bd', '#151515', '#f6f3ec'],
    ['Sauge', '#4e5c47', '#f6f2e8', '#2f3a2c', '#c9c4b1', '#5b6b52', '#f6f2e8'],
    ['Terre cuite', '#7a3b22', '#fbf3ea', '#3b2418', '#e3cdb8', '#b9552f', '#fbf3ea'],
    ['Nuit et or', '#06080f', '#0d1322', '#ece4cf', '#3a4260', '#c9a45c', '#0d1322'],
    ['Rose poudré', '#b98a84', '#fbf4f1', '#3d2f2d', '#ead5ce', '#b06a63', '#fbf4f1'],
    ['Bleu nuit', '#1d2b45', '#f4f6fa', '#1f2a3d', '#cdd5e2', '#2f4a7a', '#f4f6fa'],
    ['Bordeaux', '#4a1520', '#f7f2ea', '#2a1a1c', '#d9cdb8', '#6b1f2a', '#f7f2ea'],
    ['Wax vert et or', '#0f4d3a', '#fbf5e8', '#1f2a23', '#e3d3b0', '#c79a2e', '#1f2a23']
  ];
  // 24 more (170d): ready-made sets of the organiser's own four colours
  // (fond, papier, texte, accent), the same on every card.
  var XPALS = [
    ['Ivoire et or', '#3b2f22', '#fbf6ec', '#2b2118', '#b8893b'], ['Blanc et sauge', '#4f5d4a', '#f7f6f1', '#2e3a2c', '#7a9a6e'],
    ['Émeraude et or', '#0b3d2e', '#f6f1e3', '#13261d', '#c9a24a'], ['Bordeaux et crème', '#4b1622', '#f8f1e7', '#2b1418', '#8e2a3b'],
    ['Nuit et argent', '#0f1a2e', '#f2f4f8', '#1a2436', '#8fa3c0'], ['Rose poudré', '#c79a96', '#fcf5f3', '#4a3533', '#c0716c'],
    ['Terracotta', '#8a3f24', '#fbf1e8', '#3a2016', '#c9643a'], ['Lavande', '#5e5277', '#f7f4fa', '#362e46', '#9a86c4'],
    ['Moutarde et noir', '#1b1a17', '#fbf6e9', '#1b1a17', '#c9951c'], ['Turquoise et corail', '#0f5257', '#f3faf9', '#163a3d', '#e0664c'],
    ['Bogolan', '#3d2a1b', '#efe3cf', '#2f2014', '#9a6a3b'], ['Faso Dan Fani', '#13315c', '#f8f3e6', '#13284d', '#d9a52c'],
    ['Kente', '#1c4a2c', '#fbf3dc', '#1c2a1f', '#c8372a'], ['Wax fuchsia', '#5a0f3c', '#fdf2f7', '#3d0b28', '#d2468e'],
    ['Indigo', '#1e2a5a', '#f2f3fb', '#1b2240', '#4f63c9'], ['Olive et crème', '#4a4a26', '#f7f4e6', '#2f2f18', '#7d7d32'],
    ['Pêche', '#d98f70', '#fff6f1', '#4a2c22', '#d46e4a'], ['Menthe', '#2f6f5a', '#f2faf6', '#1f3a30', '#2f8f68'],
    ['Prune et or', '#3b1530', '#f8f0f4', '#2a1023', '#b58b45'], ['Noir et blanc', '#111111', '#ffffff', '#111111', '#111111'],
    ['Ciel', '#2b6cb0', '#f3f8fd', '#1c3046', '#2f7fcf'], ['Sable et cuivre', '#6b4a2b', '#f8efe2', '#3a2a1a', '#a85f26'],
    ['Sapin et rouge', '#123524', '#f7f3ea', '#13261c', '#a82b25'], ['Champagne', '#8a7558', '#fbf7ef', '#3b3226', '#a88a4f']
  ];
  var FONTS = [
    { id: '', name: 'Celle du modèle' },
    { id: 'classique', name: 'Classique', display: "'Cormorant Garamond',serif", body: "'Montserrat',sans-serif", script: "'Pinyon Script',cursive", q: 'Cormorant+Garamond:ital,wght@0,400;0,500;1,400&family=Montserrat:wght@300;400;500&family=Pinyon+Script' },
    { id: 'moderne', name: 'Moderne', display: "'Bodoni Moda',serif", body: "'Jost',sans-serif", script: "'Bodoni Moda',serif", q: 'Bodoni+Moda:ital,wght@0,400;0,500;1,400&family=Jost:wght@300;400;500' },
    { id: 'majestueuse', name: 'Majestueuse', display: "'Cinzel',serif", body: "'EB Garamond',serif", script: "'Parisienne',cursive", q: 'Cinzel:wght@400;600&family=EB+Garamond:ital,wght@0,400;1,400&family=Parisienne' },
    { id: 'romantique', name: 'Romantique', display: "'Playfair Display',serif", body: "'Lora',serif", script: "'Great Vibes',cursive", q: 'Playfair+Display:ital@0;1&family=Lora:ital,wght@0,400;1,400&family=Great+Vibes' },
    { id: 'epuree', name: 'Épurée', display: "'Italiana',serif", body: "'Raleway',sans-serif", script: "'Italiana',serif", q: 'Italiana&family=Raleway:wght@300;400;500' },
    { id: 'joyeuse', name: 'Joyeuse', display: "'Fraunces',serif", body: "'Josefin Sans',sans-serif", script: "'Caveat',cursive", q: 'Fraunces:ital,wght@0,400;0,600;1,400&family=Josefin+Sans:wght@300;400;600&family=Caveat:wght@500' }
  ];
  function applyLook() {
    var st = document.documentElement.style, p = PALS[+draft.pal || 0], C = colorsOf();
    ['--back', '--paper', '--ink', '--line', '--accent', '--on-accent'].forEach(function (v, i) {
      if (p && p.length > 1) st.setProperty(v, p[i + 1]); else st.removeProperty(v);
    });
    // The organiser's own colours (170) over the model's or the set's.
    if (C) {
      st.setProperty('--back', C[0]); st.setProperty('--paper', C[1]); st.setProperty('--ink', C[2]); st.setProperty('--accent', C[3]);
      st.setProperty('--line', blend(C[1], C[2], .25)); st.setProperty('--on-accent', light(C[3]) > .6 ? C[2] : C[1]);
    }
    var f = FONTS.filter(function (x) { return x.id && x.id === draft.font; })[0];
    ['display', 'body', 'script'].forEach(function (k) { if (f) st.setProperty('--' + k, f[k]); else st.removeProperty('--' + k); });
    if (f && !document.querySelector('link[data-font="' + f.id + '"]')) {
      var l = document.createElement('link'); l.rel = 'stylesheet'; l.setAttribute('data-font', f.id);
      l.href = 'https://fonts.googleapis.com/css2?family=' + f.q + '&display=swap';
      document.head.appendChild(l);
    }
  }
  applyLook();
  // The organiser's own texts and photos (170): on the organiser's screen,
  // every one begun; on the guests', the written ones only.
  for (var gn = 1; gn <= PICS; gn++) if (ORGANISER || !SERVER || draft['p:g' + gn]) picSlot(gn);
  applyHides();
  placePlus();
  Object.keys(draft).forEach(function (k) {
    if (k.indexOf('t:') === 0) {
      var el = document.querySelector('[data-edit="' + k.slice(2) + '"]');
      if (el) el.innerHTML = clean(draft[k]);
    }
  });
  applySizes();

  // ------------------------------------------------------------ pictures
  function wirePic(slot) {
    var img = slot.querySelector('img');
    var key = slot.getAttribute('data-pic');
    var d = key ? draft['p:' + key] : null;
    // A stored picture (154) is named by its key; the demo's by its data URL.
    var src = d ? (d.key ? picUrl(d.key) : d.src) : null;
    if (src) {
      if (!img) { img = new Image(); img.alt = ''; slot.insertBefore(img, slot.firstChild); }
      img.src = src;
    }
    if (d && d.pos) slot.style.setProperty('--pos', d.pos);
    if (img) {
      var ok = function () { slot.classList.add('has'); };
      img.addEventListener('load', ok);
      img.addEventListener('error', function () { img.remove(); slot.classList.remove('has'); });
      if (img.complete && img.naturalWidth > 0) ok();
    }
  }
  Array.prototype.forEach.call(document.querySelectorAll('.slot'), wirePic);

  var picker = document.createElement('input');
  picker.type = 'file'; picker.accept = 'image/*'; picker.style.display = 'none';
  document.body.appendChild(picker);
  var target = null;
  picker.addEventListener('change', function () {
    var file = picker.files[0];
    picker.value = '';
    if (!file || !target) return;
    shrink(file, 1400, function (src, canvas) {
      var slot = target, key = slot.getAttribute('data-pic');
      var img = slot.querySelector('img');
      if (!img) { img = new Image(); img.alt = ''; slot.insertBefore(img, slot.firstChild); img.addEventListener('load', function () { slot.classList.add('has'); }); }
      img.src = src;
      slot.classList.add('has');
      slot.style.setProperty('--pos', '50% 50%');
      if (!ORGANISER) {
        draft['p:' + key] = { src: src, pos: '50% 50%' };
        save();
        toast('Photo remplacée. Glissez-la pour la recadrer.');
        return;
      }
      // The organiser's: the bytes go to the uploads Worker, the card keeps
      // the key the server minted. Until it answers, the slot shows the
      // picture from this phone.
      if (!ORGANISER.uploads) { toast('Les photos ne peuvent pas être envoyées d’ici pour le moment.'); return; }
      toast('Envoi de la photo…');
      canvas.toBlob(function (blob) {
        upload(blob).then(function (j) {
          draft['p:' + key] = { key: j.key, pos: '50% 50%' };
          save();
          toast('Photo remplacée. Glissez-la pour la recadrer, puis « Enregistrer ».');
        }, function (err) {
          wirePic(slot);
          toast(err && err.message ? err.message : 'La photo n’est pas passée. Réessayez.');
        });
      }, 'image/jpeg', 0.82);
    });
  });
  function upload(blob) {
    return fetch(ORGANISER.uploads + '/v1/events/' + encodeURIComponent(ORGANISER.slug) + '/pictures?modifier=' + encodeURIComponent(ORGANISER.edit), {
      method: 'POST', headers: { 'Content-Type': 'image/jpeg' }, body: blob
    }).then(function (r) {
      return r.json().then(function (j) {
        if (!r.ok || !j || !j.key) throw new Error(j && j.error ? j.error : 'La photo n’est pas passée. Réessayez.');
        return j;
      }, function () { throw new Error('La photo n’est pas passée. Réessayez.'); });
    });
  }
  function shrink(file, max, done) {
    var url = URL.createObjectURL(file), im = new Image();
    im.onload = function () {
      var s = Math.min(1, max / Math.max(im.width, im.height));
      var c = document.createElement('canvas');
      c.width = Math.round(im.width * s); c.height = Math.round(im.height * s);
      c.getContext('2d').drawImage(im, 0, 0, c.width, c.height);
      URL.revokeObjectURL(url);
      done(c.toDataURL('image/jpeg', 0.82), c);
    };
    im.onerror = function () { URL.revokeObjectURL(url); toast('Cette image ne peut pas être lue'); };
    im.src = url;
  }

  // Tap a picture to replace it, drag it to reframe (edit mode only).
  Array.prototype.forEach.call(document.querySelectorAll('.slot[data-pic]'), wireTap);
  function wireTap(slot) {
    var down = null, moved = false, start = null;
    slot.addEventListener('pointerdown', function (e) {
      if (!document.body.classList.contains('editing')) return;
      // A tap on a text written over the picture edits the text, not the picture.
      if (e.target.closest && e.target.closest('[data-edit], a, button, input, select, textarea')) return;
      down = { x: e.clientX, y: e.clientY };
      moved = false;
      var pos = (getComputedStyle(slot).getPropertyValue('--pos') || '50% 50%').trim().split(/\s+/);
      start = [parseFloat(pos[0]) || 50, parseFloat(pos[1]) || 50];
      slot.setPointerCapture(e.pointerId);
      e.preventDefault();
    });
    slot.addEventListener('pointermove', function (e) {
      if (!down) return;
      var dx = e.clientX - down.x, dy = e.clientY - down.y;
      if (!moved && Math.hypot(dx, dy) < 6) return;
      if (!slot.classList.contains('has')) return;
      moved = true;
      var r = slot.getBoundingClientRect();
      var x = Math.max(0, Math.min(100, start[0] - dx / r.width * 100));
      var y = Math.max(0, Math.min(100, start[1] - dy / r.height * 100));
      slot.style.setProperty('--pos', x.toFixed(1) + '% ' + y.toFixed(1) + '%');
    });
    function up(e) {
      if (!down) return;
      down = null;
      var key = slot.getAttribute('data-pic');
      if (moved) {
        var d = draft['p:' + key] || {};
        d.pos = slot.style.getPropertyValue('--pos');
        draft['p:' + key] = d;
        save();
      } else {
        target = slot;
        picker.click();
      }
    }
    slot.addEventListener('pointerup', up);
    slot.addEventListener('pointercancel', function () { down = null; });
  }

  // ------------------------------------------------------------- editor
  if (card && (!SERVER || ORGANISER)) {
    var bar = document.createElement('div');
    bar.className = 'edbar';
    var opts = Object.keys(PRESETS).map(function (k) { return '<option value="' + k + '">' + PRESETS[k].label + '</option>'; }).join('');
    bar.innerHTML =
      '<button type="button" class="ed-toggle">Modifier cette carte</button>' +
      // The organiser's panel folds away (170b): a scroll or a tap on a text
      // leaves only « Outils » and « Enregistrer »; « Outils » opens it again.
      (ORGANISER ? '<div class="ed-mini" hidden><button type="button" class="ed-unfold">Outils</button><span class="ed-sizes" hidden><button type="button" data-sz="-1" aria-label="Texte plus petit">A−</button><button type="button" data-sz="1" aria-label="Texte plus grand">A+</button></span><button type="button" class="ed-save ed-mini-save">Enregistrer</button></div>' : '') +
      '<div class="ed-tools" hidden>' +
      (ORGANISER ? '<div class="ed-head"><b>Les outils de la carte</b><button type="button" class="ed-fold">Réduire</button></div>' : '') +
      '<label class="ed-type">Événement <select>' + opts + '</select></label>' +
      '<div class="ed-look"><div class="ed-pals" role="group" aria-label="Couleurs">' +
      PALS.map(function (p, i) {
        var bg = p.length > 1 ? 'linear-gradient(135deg,' + p[2] + ' 50%,' + p[5] + ' 50%)' : 'conic-gradient(#f6f3ec 0 25%,#5b6b52 0 50%,#c9a45c 0 75%,#151515 0)';
        return '<button type="button" class="ed-pal" data-p="' + i + '" title="' + p[0] + '" aria-label="' + p[0] + '" style="background:' + bg + '"></button>';
      }).join('') + '</div>' +
      '<select class="ed-font" aria-label="Écriture">' + FONTS.map(function (f) { return '<option value="' + f.id + '">Aa · ' + f.name + '</option>'; }).join('') + '</select></div>' +
      '<div class="ed-colors" role="group" aria-label="Vos couleurs"></div>' +
      '<div class="ed-palx-wrap"><button type="button" class="ed-palx-btn" aria-expanded="false">+ 24 palettes</button><div class="ed-palx" hidden>' +
      XPALS.map(function (p, i) { return '<button type="button" data-x="' + i + '" title="' + p[0] + '" aria-label="' + p[0] + '" style="background:linear-gradient(135deg,' + p[2] + ' 0 50%,' + p[4] + ' 50% 75%,' + p[1] + ' 75%)"></button>'; }).join('') + '</div></div>' +
      '<div class="ed-selrow" hidden><span>Le texte choisi :</span><button type="button" data-sz="-1">A− plus petit</button><button type="button" data-sz="1">A+ plus grand</button></div>' +
      '<div class="ed-sw" role="group" aria-label="Sur la carte"></div>' +
      '<div class="ed-add"><button type="button" class="ed-plus-text">+ Un texte</button><button type="button" class="ed-plus-pic">+ Une photo</button></div>' +
      '<p class="ed-hint">Touchez un texte pour l’écrire, videz-le pour l’enlever ; une photo pour la remplacer, glissez-la pour la recadrer.</p>' +
      '<div class="ed-row">' +
      (ORGANISER ? '<button type="button" class="ed-done ed-save">Enregistrer</button>'
        : '<button type="button" class="ed-reset">Réinitialiser</button><button type="button" class="ed-done">Terminé</button>') +
      '</div></div>';
    document.body.appendChild(bar);
    document.body.classList.add('has-edbar');
    var sel = bar.querySelector('.ed-type select');
    function drawLook() {
      var C = colorsOf();
      Array.prototype.forEach.call(bar.querySelectorAll('.ed-pal'), function (b) { b.setAttribute('aria-pressed', String(!C && +b.getAttribute('data-p') === (+draft.pal || 0))); });
      bar.querySelector('.ed-font').value = draft.font || '';
      // the organiser's own colours: the card's as they stand, to start from
      var cs = getComputedStyle(document.documentElement), now = C || ['--back', '--paper', '--ink', '--accent'].map(function (v) { return toHex6(cs.getPropertyValue(v)); });
      bar.querySelector('.ed-colors').innerHTML = [['Fond', 0], ['Papier', 1], ['Texte', 2], ['Accent', 3]].map(function (x) {
        return '<label class="ed-col"><input type="color" data-c="' + x[1] + '" value="' + now[x[1]] + '"><span>' + x[0] + '</span></label>';
      }).join('') + (C ? '<button type="button" class="ed-col-reset">Couleurs du modèle</button>' : '');
      // what the card shows: only what this card has
      var sws = [['word', 'Le mot'], ['prog', 'Programme'], ['times', 'Horaires'], ['infos', 'Bon à savoir'], ['pics', 'Photos'], ['rsvp', 'Réponse des invités'], ['qr', 'Carte d’invité (QR)'], ['album', 'Album'], ['cd', 'Compte à rebours'], ['foot', 'Pied de page']];
      bar.querySelector('.ed-sw').innerHTML = sws.filter(function (x) {
        if (x[0] === 'times') return !!document.querySelector('[data-prog] [data-t]');
        if (x[0] === 'cd') return !!document.querySelector('[data-count]');
        if (x[0] === 'qr') return !!SERVER;
        return !!sectionOf(x[0]);
      }).map(function (x) { return '<label class="ed-s"><input type="checkbox" data-sw="' + x[0] + '"' + (off(x[0]) ? '' : ' checked') + '> ' + x[1] + '</label>'; }).join('');
    }
    function toHex6(v) {
      v = String(v || '').trim();
      if (/^#[0-9a-f]{6}$/i.test(v)) return v.toLowerCase();
      if (/^#[0-9a-f]{3}$/i.test(v)) return ('#' + v[1] + v[1] + v[2] + v[2] + v[3] + v[3]).toLowerCase();
      var m = v.match(/\d+/g); return m && m.length >= 3 ? hexOf(m.slice(0, 3).map(Number)) : '#888888';
    }
    Array.prototype.forEach.call(bar.querySelectorAll('.ed-pal'), function (b) {
      b.addEventListener('click', function () { draft.pal = +b.getAttribute('data-p'); delete draft['t:colors']; applyLook(); drawLook(); save(); });
    });
    bar.querySelector('.ed-font').addEventListener('change', function (e) { draft.font = e.target.value; applyLook(); save(); });
    // a colour as it is picked, live; kept when the choice is made
    bar.querySelector('.ed-colors').addEventListener('input', function (e) {
      var t = e.target; if (!t.matches('[data-c]')) return;
      document.documentElement.style.setProperty(['--back', '--paper', '--ink', '--accent'][+t.dataset.c], t.value);
    });
    bar.querySelector('.ed-colors').addEventListener('change', function (e) {
      var t = e.target; if (!t.matches('[data-c]')) return;
      var c = Array.prototype.map.call(bar.querySelectorAll('.ed-colors [data-c]'), function (i) { return String(i.value).toLowerCase(); });
      draft['t:colors'] = c.join(','); applyLook(); drawLook(); save();
    });
    bar.querySelector('.ed-colors').addEventListener('click', function (e) {
      if (!e.target.closest('.ed-col-reset')) return;
      delete draft['t:colors']; applyLook(); drawLook(); save();
    });
    bar.querySelector('.ed-sw').addEventListener('change', function (e) {
      var t = e.target; if (!t.matches('[data-sw]')) return;
      setOff(t.dataset.sw, !t.checked); applyHides(); placePlus(); save();
    });
    // 24 more palettes (170d): a ready-made set of the four colours
    bar.querySelector('.ed-palx-btn').addEventListener('click', function (e) {
      var g = bar.querySelector('.ed-palx'); g.hidden = !g.hidden; e.currentTarget.setAttribute('aria-expanded', String(!g.hidden));
    });
    bar.querySelector('.ed-palx').addEventListener('click', function (e) {
      var b = e.target.closest('[data-x]'); if (!b) return;
      var p = XPALS[+b.getAttribute('data-x')]; draft['t:colors'] = [p[1], p[2], p[3], p[4]].join(',');
      applyLook(); drawLook(); applySizes(); save(); toast('Couleurs : ' + p[0]);
    });
    // The chosen text (170d): the last one tapped, outlined; A− / A+ size it.
    var SEL = null;
    function drawSel() {
      Array.prototype.forEach.call(bar.querySelectorAll('.ed-sizes, .ed-selrow'), function (x) { x.hidden = !SEL; });
    }
    document.addEventListener('focusin', function (e) {
      var el = e.target.closest && e.target.closest('[data-edit]');
      if (!el || !document.body.classList.contains('editing')) return;
      if (SEL && SEL !== el) SEL.classList.remove('is-sel');
      SEL = el; el.classList.add('is-sel'); drawSel();
    });
    bar.addEventListener('click', function (e) {
      var b = e.target.closest('[data-sz]'); if (!b || !SEL) return;
      var key = SEL.getAttribute('data-edit'), cur = sizeMap()[key] || 'M';
      var next = STEPS[Math.max(0, Math.min(STEPS.length - 1, STEPS.indexOf(cur) + (+b.getAttribute('data-sz'))))];
      if (next === cur) { toast(next === 'XL' ? 'C’est la plus grande taille.' : 'C’est la plus petite taille.'); return; }
      setSize(key, next); applySizes(); save();
      toast({ S: 'Petit', M: 'Taille du modèle', L: 'Grand', XL: 'Très grand' }[next]);
    });
    // The lists' chips (170d): take a step or an info away, put it back, add one.
    document.addEventListener('click', function (ev) {
      var b = ev.target.closest && ev.target.closest('.li-ed button');
      if (!b || !document.body.classList.contains('editing')) return;
      ev.preventDefault();
      var kind = b.closest('.li-ed').getAttribute('data-list'), L = LISTS[kind];
      if (b.classList.contains('li-add')) {
        var ids = addIds(kind), id = Math.max.apply(null, [0].concat(ids)) + 1; ids.push(id); setAddIds(kind, ids);
        applyHides(); placePlus(); applySizes(); save();
        var li = document.querySelector(L.sel + ' li[data-la="' + id + '"]'), f = li && li.querySelector('[data-edit]');
        if (f) { f.scrollIntoView({ behavior: 'smooth', block: 'center' }); f.focus(); }
        toast(kind === 'prog' ? 'Écrivez l’heure, le nom et le détail de l’étape.' : 'Écrivez le titre et le détail.');
        return;
      }
      if (b.hasAttribute('data-a')) {
        var a = +b.getAttribute('data-a');
        setAddIds(kind, addIds(kind).filter(function (x) { return x !== a; }));
        L.fields.forEach(function (f2) { delete draft['t:' + L.key + '-' + a + '-' + f2[1]]; });
        toast(kind === 'prog' ? 'Étape retirée.' : 'Info retirée.');
      } else {
        var k = kind + '-' + b.getAttribute('data-i'), was = off(k);
        setOff(k, !was); toast(was ? 'Remise sur la carte.' : 'Retirée de la carte. Touchez-la encore pour la remettre.');
      }
      applyHides(); placePlus(); applySizes(); save();
    });
    bar.querySelector('.ed-plus-text').addEventListener('click', function () {
      // a new text, the last of those under the intro
      var l = plusList(), n = Math.max.apply(null, [0].concat(l.map(function (x) { return x.n; }), numKeys(/^t:plus-(\d+)$/))) + 1, at = -1;
      l.forEach(function (x, m) { if ((EFF[x.n] || x.at) === 'intro') at = m; });
      l.splice(at + 1, 0, { n: n, at: 'intro' }); setPlusList(l); placePlus(); save();
      var p = document.querySelector('[data-edit="plus-' + n + '"]');
      if (!p) { toast('Pas de place pour un texte sur cette carte.'); return; }
      p.setAttribute('contenteditable', 'true'); p.scrollIntoView({ behavior: 'smooth', block: 'center' }); p.focus();
      toast('Écrivez votre texte. « Monter » et « Descendre » le déplacent.');
    });
    // an added text's buttons: up, down, take it away (170c)
    document.addEventListener('click', function (ev) {
      var b = ev.target.closest && ev.target.closest('.xmove button');
      if (!b || !document.body.classList.contains('editing')) return;
      ev.preventDefault();
      var n = +b.parentNode.getAttribute('data-pn'), act = b.getAttribute('data-pm');
      if (act === 'del') {
        delete draft['t:plus-' + n]; setPlusList(plusList().filter(function (x) { return x.n !== n; }));
        placePlus(); save(); toast('Texte retiré.');
      } else movePlus(n, act === 'up' ? -1 : 1);
    });
    bar.querySelector('.ed-plus-pic').addEventListener('click', function () {
      var s = picSlot(++PICS); if (!s) { PICS--; toast('Pas de place pour une photo sur cette carte.'); return; }
      wirePic(s); wireTap(s); s.scrollIntoView({ behavior: 'smooth', block: 'center' });
      toast('Touchez le cadre pour choisir la photo.');
    });
    drawLook();
    var def = card.getAttribute('data-type') || 'mariage';
    sel.value = draft.type || def;
    sel.addEventListener('change', function () { applyPreset(sel.value); });
    var folded = false, foldY = 0, foldAt = 0;
    function fold(on) {
      if (!ORGANISER) return;
      folded = on;
      var editing = document.body.classList.contains('editing');
      bar.querySelector('.ed-tools').hidden = on || !editing;
      bar.querySelector('.ed-mini').hidden = !on || !editing;
      if (!on) { foldY = window.scrollY; foldAt = Date.now(); }
    }
    function setEditing(on) {
      document.body.classList.toggle('editing', on);
      bar.querySelector('.ed-toggle').hidden = on;
      bar.querySelector('.ed-tools').hidden = !on || folded;
      if (ORGANISER) bar.querySelector('.ed-mini').hidden = !on || !folded;
      editables().forEach(function (el) {
        if (on) el.setAttribute('contenteditable', 'true'); else el.removeAttribute('contenteditable');
      });
      if (on) toast('Mode édition'); else if (!ORGANISER) toast('Carte enregistrée sur ce téléphone');
    }
    bar.querySelector('.ed-toggle').addEventListener('click', function () { setEditing(true); });
    if (ORGANISER) {
      // The organiser's « Enregistrer »: the draft goes to the server
      // (event_content_save, 154) with the edit token; the guests see it
      // at their next visit.
      // « Enregistrer » sits in the panel and in the folded bar: one state for both.
      var saveBtns = Array.prototype.slice.call(bar.querySelectorAll('.ed-save'));
      var saveBtn = { set textContent(v) { saveBtns.forEach(function (b) { b.textContent = v; }); }, set disabled(v) { saveBtns.forEach(function (b) { b.disabled = v; }); } };
      markDirty = function () { saveBtn.textContent = 'Enregistrer'; saveBtn.disabled = false; };
      bar.querySelector('.ed-fold').addEventListener('click', function () { fold(true); });
      bar.querySelector('.ed-unfold').addEventListener('click', function () { fold(false); });
      // The panel gets out of the way: a scroll of the card, or a text taken to write.
      window.addEventListener('scroll', function () { if (!folded && Math.abs(window.scrollY - foldY) > 48 && Date.now() - foldAt > 500) fold(true); }, { passive: true });
      document.addEventListener('focusin', function (e) { if (!folded && e.target.closest && e.target.closest('[data-edit]')) fold(true); });
      function onSave() {
        editables().forEach(function (el) { el.blur(); });
        // an added text left empty is not kept
        Object.keys(draft).forEach(function (k) { if (/^t:plus-\d+$/.test(k) && !plusText(k)) delete draft[k]; });
        setPlusList(plusList().filter(function (x) { return plusText('t:plus-' + x.n); }));
        Object.keys(LISTS).forEach(function (kind) {
          var L = LISTS[kind];
          setAddIds(kind, addIds(kind).filter(function (id) { return L.fields.some(function (f) { return plusText('t:' + L.key + '-' + id + '-' + f[1]); }); }));
        });
        saveBtn.disabled = true; saveBtn.textContent = 'Envoi…';
        fetch(SERVER.api.url.replace(/\/+$/, '') + '/rest/v1/rpc/event_content_save', {
          method: 'POST',
          headers: { apikey: SERVER.api.key, Authorization: 'Bearer ' + SERVER.api.key, 'Content-Type': 'application/json' },
          body: JSON.stringify({ p_slug: SERVER.slug, p_edit: ORGANISER.edit, p_content: draft })
        }).then(function (r) {
          if (r.ok) { dirty = false; saveBtn.textContent = 'Enregistré'; toast('Carte enregistrée. Vos invités la verront ainsi.'); setEditing(false); return; }
          return r.json().then(function (j) { throw new Error(j && (j.message || j.hint) || 'La carte n’est pas enregistrée.'); });
        }).catch(function (err) {
          markDirty();
          toast(err && err.message ? err.message : 'La carte n’est pas enregistrée. Réessayez.');
        });
      }
      saveBtns.forEach(function (b) { b.addEventListener('click', onSave); });
      window.addEventListener('beforeunload', function (e) { if (dirty) { e.preventDefault(); e.returnValue = ''; } });
      setEditing(true); fold(false);
    } else {
      bar.querySelector('.ed-done').addEventListener('click', function () { setEditing(false); });
      bar.querySelector('.ed-reset').addEventListener('click', function () {
        draft = {};
        try { localStorage.removeItem(KEY); } catch (e) {}
        location.reload();
      });
    }
    // Delegated: the words a type change writes anew are written in place too.
    var t;
    document.addEventListener('input', function (e) {
      var el = e.target.closest && e.target.closest('[data-edit]');
      if (!el || !document.body.classList.contains('editing')) return;
      draft['t:' + el.getAttribute('data-edit')] = el.innerHTML;
      clearTimeout(t); t = setTimeout(save, 400);
    });
    document.addEventListener('keydown', function (e) {
      var el = e.target.closest && e.target.closest('[data-edit]');
      if (el && e.key === 'Enter' && el.tagName !== 'P' && el.tagName !== 'DIV') { e.preventDefault(); el.blur(); }
    });
  }

  // ----------------------------------------------------------------- RSVP
  Array.prototype.forEach.call(document.querySelectorAll('form.rsvp'), function (f) {
    var key = 'rsvp-' + (f.getAttribute('data-key') || id);
    var ok = f.querySelector('.ok');
    function show(d) {
      var name = d.name || 'Merci';
      var n = parseInt(d.n, 10) || 1;
      ok.textContent = d.rep === 'non'
        ? 'Merci ' + name + ', nous penserons à vous ce jour-là.'
        : d.rep === 'mot'
          ? 'Merci ' + name + '. Votre mot est transmis à la famille.'
          : 'Merci ' + name + ' ! Votre présence est notée' + (n > 1 ? ' pour ' + n + ' personnes' : '') + '.';
      ok.classList.add('on');
      drawPass(d);
    }
    // The guest's pass (158): the answer's id, given by the server, drawn as
    // a QR that opens /e/<slug>/invite/<id> — their name, how many, the
    // event — for the door. Nothing on a sample or an answer kept before.
    function drawPass(d) {
      var old = f.querySelector('.pass'); if (old) old.parentNode.removeChild(old);
      if (!d.pass || !SERVER || SERVER.demo || d.rep === 'non' || off('qr')) return;
      var box = document.createElement('div'); box.className = 'pass';
      box.innerHTML = '<div class="pass-qr" role="img" aria-label="QR code de votre carte d’invité"></div><div><b></b><br><small>Carte d’invité · à présenter à l’entrée</small></div>';
      box.querySelector('b').textContent = d.name || 'Invité';
      ok.parentNode.insertBefore(box, ok.nextSibling);
      var draw = function () {
        try {
          var q = qrcode(0, 'M');
          q.addData(location.origin + '/e/' + encodeURIComponent(SERVER.slug) + '/invite/' + d.pass); q.make();
          box.querySelector('.pass-qr').innerHTML = q.createSvgTag({ cellSize: 3, margin: 0, scalable: true });
        } catch (e) { box.querySelector('.pass-qr').textContent = 'QR'; }
      };
      if (window.qrcode) { draw(); return; }
      var s = document.createElement('script');
      s.src = 'https://cdnjs.cloudflare.com/ajax/libs/qrcode-generator/1.4.4/qrcode.min.js'; s.onload = draw;
      document.head.appendChild(s);
    }
    // A card that sells tickets (161): the answer is a ticket, asked on the
    // ticket page; the form gives way to its button.
    if (SERVER && SERVER.tickets && !SERVER.demo) {
      var tb = document.createElement('div'); tb.className = 'tickets';
      tb.innerHTML = '<p>Cet événement se fait sur billet. Réservez vos places, payez l’organisateur, recevez vos billets avec leur QR code.</p>' +
        '<a class="btn" href="/e/' + encodeURIComponent(SERVER.slug) + '/billets' + (SERVER.preview ? '?apercu=' + encodeURIComponent(SERVER.preview) : '') + '">Réserver mes billets</a>';
      f.parentNode.insertBefore(tb, f); f.hidden = true; f.style.display = 'none';
      return;
    }
    // The guest's WhatsApp, if they wish (159): the organiser's reminder
    // the day before goes through it. Collected with the answer (extra).
    if (SERVER && !SERVER.demo && !f.querySelector('[name=whatsapp]')) {
      var submit = f.querySelector('button[type=submit]'), wa = document.createElement('label');
      wa.className = 'f';
      wa.innerHTML = 'WhatsApp, si vous voulez un rappel la veille <input name="whatsapp" inputmode="tel" autocomplete="tel" placeholder="+226 70 00 00 00" maxlength="24">';
      if (submit) submit.parentNode.insertBefore(wa, submit); else f.appendChild(wa);
    }
    try { var saved = JSON.parse(localStorage.getItem(key) || 'null'); if (saved) show(saved); } catch (e) {}
    if (SERVER && SERVER.rsvp_on === false) {
      Array.prototype.forEach.call(f.querySelectorAll('input, select, textarea, button'), function (c) { c.disabled = true; });
      ok.textContent = 'Les réponses sont fermées pour cet événement.';
      ok.classList.add('on');
    }
    f.addEventListener('submit', function (e) {
      e.preventDefault();
      var fd = new FormData(f), d = {};
      fd.forEach(function (v, k) { d[k] = String(v).trim(); });
      // A design's sample (155c, SERVER.demo): the answer stays here.
      if (!SERVER || SERVER.demo) {
        show(d);
        try { localStorage.setItem(key, JSON.stringify(d)); } catch (e2) {}
        toast('Réponse envoyée');
        return;
      }
      var extra = {};
      Object.keys(d).forEach(function (k) { if (['name', 'n', 'rep', 'msg'].indexOf(k) < 0 && d[k]) extra[k] = d[k]; });
      var btn = f.querySelector('button[type=submit]');
      if (btn) btn.disabled = true;
      fetch(SERVER.api.url.replace(/\/+$/, '') + '/rest/v1/rpc/event_rsvp', {
        method: 'POST',
        headers: { apikey: SERVER.api.key, Authorization: 'Bearer ' + SERVER.api.key, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          p_slug: SERVER.slug, p_preview: SERVER.preview || null, p_name: d.name || '',
          p_people: parseInt(d.n, 10) || (d.rep === 'mot' ? 0 : 1), p_answer: d.rep || 'oui',
          p_message: d.msg || null, p_extra: extra
        })
      }).then(function (r) {
        if (r.ok) {
          // The answer's id: the guest's pass (158).
          return r.json().then(function (id) { if (typeof id === 'string') d.pass = id; }, function () {}).then(function () {
            show(d); try { localStorage.setItem(key, JSON.stringify(d)); } catch (e2) {} toast('Réponse envoyée');
          });
        }
        return r.json().then(function (j) { throw new Error(j && (j.message || j.hint) || 'La réponse n’est pas passée.'); });
      }).catch(function (err) {
        ok.textContent = err && err.message ? err.message : 'La réponse n’est pas passée. Réessayez.';
        ok.classList.add('on');
      }).then(function () { if (btn) btn.disabled = false; });
    });
  });

  // ------------------------------------------------- the guests' album
  Array.prototype.forEach.call(document.querySelectorAll('.album-box'), function (box) {
    var input = box.querySelector('input[type=file]');
    var grid = box.querySelector('.album');
    var count = box.querySelector('.count');
    var who = box.querySelector('input[name=who]');
    var drop = box.querySelector('.drop');
    var n = grid.querySelectorAll('figure').length;
    function counted() { if (count) count.textContent = n + (n > 1 ? ' photos' : ' photo'); }
    function figureFor(src, full, name) {
      var fig = document.createElement('figure');
      var img = new Image();
      img.src = src; img.alt = ''; img.loading = 'lazy';
      fig.appendChild(img);
      var cap = document.createElement('figcaption');
      cap.textContent = name || 'Un invité';
      fig.appendChild(cap);
      fig.addEventListener('click', function () { lightbox(full); });
      return fig;
    }
    if (SERVER) {
      // The card's album (155): the guests' pictures live with the event,
      // read from it and sent to the uploads Worker with the card's link.
      // Closed by the organiser, or no Worker to send to: the box says so.
      if (SERVER.demo) { box.hidden = true; return; }
      if (SERVER.album_on === false || !SERVER.uploads) {
        box.hidden = true;
        box.insertAdjacentHTML('afterend', '<p class="note">' + (SERVER.album_on === false
          ? 'L’album est fermé pour cet événement.'
          : 'L’album des invités n’est pas disponible pour le moment.') + '</p>');
        return;
      }
      grid.innerHTML = ''; n = 0; counted();
      var note = box.querySelector('.note');
      if (note) note.textContent = 'Vos photos arrivent dans l’album de l’événement, sous votre prénom, visibles par tous les invités.';
      var meta = box.querySelectorAll('.album-meta > span');
      if (meta.length > 1) meta[meta.length - 1].textContent = 'Visibles par tous les invités';
      var headers = { apikey: SERVER.api.key, Authorization: 'Bearer ' + SERVER.api.key, 'Content-Type': 'application/json' };
      // The guest's pass (164): their answer on this card (158), or the
      // tickets this browser booked for it (161) — five photos each when
      // the organiser limits the album.
      var passFor = function () {
        try {
          var f = document.querySelector('form.rsvp');
          var saved = f && JSON.parse(localStorage.getItem('rsvp-' + (f.getAttribute('data-key') || '')) || 'null');
          if (saved && saved.pass && saved.rep !== 'non') return saved.pass;
        } catch (e) {}
        try {
          var b = JSON.parse(localStorage.getItem('mk-billets') || '[]');
          for (var i = b.length - 1; i >= 0; i--) if (b[i] && b[i].slug === SERVER.slug && b[i].id) return b[i].id;
        } catch (e) {}
        return '';
      };
      var rules = { review: false, limit: false };
      fetch(SERVER.api.url.replace(/\/+$/, '') + '/rest/v1/rpc/event_album_rules', {
        method: 'POST', headers: headers,
        body: JSON.stringify({ p_slug: SERVER.slug, p_preview: SERVER.preview || null })
      }).then(function (r) { return r.ok ? r.json() : null; }).then(function (j) {
        if (!j) return;
        rules = j;
        var said = [];
        if (j.limit) said.push((j.per_pass || 5) + ' photos par invité : répondez d’abord à l’invitation (ou réservez votre billet) sur ce téléphone.');
        if (j.review) said.push('Elles apparaissent dans l’album une fois validées par l’organisateur.');
        if (said.length && note) note.textContent = said.join(' ');
        if (j.review && meta.length > 1) meta[meta.length - 1].textContent = 'Validées par l’organisateur';
      }).catch(function () {});
      fetch(SERVER.api.url.replace(/\/+$/, '') + '/rest/v1/rpc/event_album', {
        method: 'POST', headers: headers,
        body: JSON.stringify({ p_slug: SERVER.slug, p_preview: SERVER.preview || null })
      }).then(function (r) { return r.ok ? r.json() : []; }).then(function (list) {
        (Array.isArray(list) ? list : []).forEach(function (p) {
          if (p && p.key) { grid.appendChild(figureFor(picUrl(p.key) + '?w=400', picUrl(p.key), p.guest)); n++; }
        });
        counted();
      }).catch(function () {});
      var send = function (file) {
        if (!file.type || file.type.indexOf('image/') !== 0) return Promise.resolve(null);
        var name = (who && who.value.trim()) || '';
        return new Promise(function (res) {
          shrink(file, 1400, function (src, canvas) {
            canvas.toBlob(function (blob) {
              fetch(SERVER.uploads + '/v1/events/' + encodeURIComponent(SERVER.slug) + '/album?apercu=' + encodeURIComponent(SERVER.preview || '') + '&invite=' + encodeURIComponent(name) + '&pass=' + encodeURIComponent(passFor()), {
                method: 'POST', headers: { 'Content-Type': 'image/jpeg' }, body: blob
              }).then(function (r) {
                return r.json().then(function (j) {
                  if (!r.ok || !j || !j.key) throw new Error(j && j.error ? j.error : 'La photo n’est pas passée. Réessayez.');
                  return j;
                }, function () { throw new Error('La photo n’est pas passée. Réessayez.'); });
              }).then(function (j) {
                // Waiting for the organiser's yes (164): not in the album yet.
                if (!rules.review) { grid.insertBefore(figureFor(src, picUrl(j.key), name), grid.firstChild); n++; counted(); }
                res(j);
              }, function (err) { toast(err && err.message ? err.message : 'La photo n’est pas passée. Réessayez.'); res(null); });
            }, 'image/jpeg', 0.82);
          });
        });
      };
      var sendAll = function (files) {
        if (!files.length) return;
        toast(files.length > 1 ? 'Envoi des photos…' : 'Envoi de la photo…');
        Promise.all(files.map(send)).then(function (r) {
          var k = r.filter(Boolean).length;
          if (k && rules.review) toast(k > 1 ? k + ' photos envoyées : visibles après validation' : 'Photo envoyée : visible après validation');
          else if (k) toast(k > 1 ? k + ' photos ajoutées à l’album' : 'Photo ajoutée à l’album');
        });
      };
      input.addEventListener('change', function () {
        var files = Array.prototype.slice.call(input.files);
        input.value = '';
        sendAll(files);
      });
      if (drop) {
        drop.addEventListener('dragover', function (e) { e.preventDefault(); drop.classList.add('over'); });
        drop.addEventListener('dragleave', function () { drop.classList.remove('over'); });
        drop.addEventListener('drop', function (e) {
          e.preventDefault(); drop.classList.remove('over');
          sendAll(Array.prototype.slice.call(e.dataTransfer.files));
        });
      }
      return;
    }
    function add(file) {
      if (!file.type || file.type.indexOf('image/') !== 0) return;
      var url = URL.createObjectURL(file);
      grid.insertBefore(figureFor(url, url, (who && who.value.trim()) || ''), grid.firstChild);
      n++;
    }
    function done(k) {
      counted();
      toast(k > 1 ? k + ' photos ajoutées à l’album' : 'Photo ajoutée à l’album');
    }
    input.addEventListener('change', function () {
      var files = Array.prototype.slice.call(input.files);
      files.forEach(add);
      input.value = '';
      if (files.length) done(files.length);
    });
    if (drop) {
      drop.addEventListener('dragover', function (e) { e.preventDefault(); drop.classList.add('over'); });
      drop.addEventListener('dragleave', function () { drop.classList.remove('over'); });
      drop.addEventListener('drop', function (e) {
        e.preventDefault(); drop.classList.remove('over');
        var files = Array.prototype.slice.call(e.dataTransfer.files);
        files.forEach(add);
        if (files.length) done(files.length);
      });
    }
    Array.prototype.forEach.call(grid.querySelectorAll('figure img'), function (img) {
      img.parentNode.addEventListener('click', function () { if (img.parentNode.contains(img)) lightbox(img.src); });
    });
  });

  // ------------------------------------------------------------ countdown
  Array.prototype.forEach.call(document.querySelectorAll('[data-count]'), function (el) {
    var t = new Date(el.getAttribute('data-count')).getTime();
    var d = el.querySelector('[data-d]'), h = el.querySelector('[data-h]'), m = el.querySelector('[data-m]');
    function tick() {
      var ms = t - Date.now();
      if (ms <= 0) { el.textContent = 'C’est aujourd’hui'; return; }
      if (d) d.textContent = Math.floor(ms / 864e5);
      if (h) h.textContent = Math.floor(ms % 864e5 / 36e5);
      if (m) m.textContent = Math.floor(ms % 36e5 / 6e4);
    }
    tick();
    setInterval(tick, 30000);
  });

  // ------------------------------------------- copy a line (a number…)
  Array.prototype.forEach.call(document.querySelectorAll('[data-copy]'), function (b) {
    b.addEventListener('click', function () {
      var text = b.getAttribute('data-copy');
      var p = navigator.clipboard && navigator.clipboard.writeText ? navigator.clipboard.writeText(text) : Promise.reject();
      p.then(function () { toast('Copié'); }, function () { toast(text); });
    });
  });

  window.carteToast = toast;
})();
