// Marakaj Studio — the editor (171). The card drawn as its guests will see
// it, every part of it the organiser's to write, add, move, style or take
// away. Saved to the server with the card's edit token (event_doc_save),
// kept on the phone as a draft in between, twenty versions to go back to.
(function () {
  'use strict';
  var S = window.Studio, U = S.util, esc = U.esc;
  var BOOT = window.CARTE || {};
  var ctx = {
    slug: BOOT.slug, title: BOOT.title || '', kind: BOOT.kind || 'autre', card: BOOT.card, date: BOOT.date, time: BOOT.time, place: BOOT.place || '',
    rsvp_on: BOOT.rsvp_on !== false, album_on: BOOT.album_on !== false, tickets: BOOT.tickets === true, preview: BOOT.preview || null,
    api: BOOT.api || {}, uploads: BOOT.uploads || null, edit: BOOT.edit, content: BOOT.content || {}, editing: true, demo: false
  };
  var DRAFT = 'studio-' + (ctx.slug || 'demo');
  var doc = null, savedJson = '', savedAt = BOOT.doc_saved_at || null, converted = false;
  var hist = [], fut = [], sel = null, textSel = null, preview = false, inserting = null;

  // ------------------------------------------------------------ the frame
  var app = document.getElementById('app');
  var I = {
    close: '<svg viewBox="0 0 24 24"><path d="M6 6l12 12M18 6 6 18"/></svg>',
    undo: '<svg viewBox="0 0 24 24"><path d="M9 14 4 9l5-5"/><path d="M4 9h10a6 6 0 0 1 0 12h-3"/></svg>',
    redo: '<svg viewBox="0 0 24 24"><path d="m15 14 5-5-5-5"/><path d="M20 9H10a6 6 0 0 0 0 12h3"/></svg>',
    eye: '<svg viewBox="0 0 24 24"><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/></svg>',
    blocks: '<svg viewBox="0 0 24 24"><rect x="4" y="4" width="16" height="5" rx="1"/><rect x="4" y="11" width="16" height="4" rx="1"/><rect x="4" y="17" width="16" height="3" rx="1"/></svg>',
    theme: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><circle cx="8.5" cy="9" r="1.4"/><circle cx="12" cy="7" r="1.4"/><circle cx="15.5" cy="9" r="1.4"/><path d="M12 21a2.5 2.5 0 0 1 0-5h2a3 3 0 0 0 3-3"/></svg>',
    plus: '<svg viewBox="0 0 24 24"><path d="M12 5v14M5 12h14"/></svg>',
    more: '<svg viewBox="0 0 24 24"><circle cx="5" cy="12" r="1.6"/><circle cx="12" cy="12" r="1.6"/><circle cx="19" cy="12" r="1.6"/></svg>',
    gear: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/></svg>',
    up: '<svg viewBox="0 0 24 24"><path d="M12 19V5M5 12l7-7 7 7"/></svg>',
    down: '<svg viewBox="0 0 24 24"><path d="M12 5v14M19 12l-7 7-7-7"/></svg>',
    copy: '<svg viewBox="0 0 24 24"><rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V5a1 1 0 0 0-1-1H5a1 1 0 0 0-1 1v10a1 1 0 0 0 1 1h3"/></svg>',
    hide: '<svg viewBox="0 0 24 24"><path d="M3 3l18 18M10.6 5.1A9.7 9.7 0 0 1 12 5c6.5 0 10 7 10 7a17 17 0 0 1-3.2 4.2M6.6 6.6A17 17 0 0 0 2 12s3.5 7 10 7a9.5 9.5 0 0 0 5.4-1.6"/></svg>',
    trash: '<svg viewBox="0 0 24 24"><path d="M4 7h16M10 11v6M14 11v6M5 7l1 13h12l1-13M9 7V4h6v3"/></svg>'
  };
  app.innerHTML =
    '<header class="ed-top"><button class="ed-ib" id="edClose" aria-label="Fermer">' + I.close + '</button>' +
    '<div class="ed-title"><span id="edName"></span><small id="edState">Studio</small></div>' +
    '<button class="ed-ib" id="edUndo" aria-label="Annuler" disabled>' + I.undo + '</button><button class="ed-ib" id="edRedo" aria-label="Rétablir" disabled>' + I.redo + '</button>' +
    '<button class="ed-ib" id="edPreview" aria-label="Voir comme un invité">' + I.eye + '</button><button class="ed-ib acc" id="edSave">Enregistrer</button></header>' +
    '<div id="canvas" class="st-root"></div>' +
    '<nav class="ed-nav" id="edNav"><button data-nav="blocks">' + I.blocks + 'Blocs</button><button data-nav="theme">' + I.theme + 'Thème</button>' +
    '<button data-nav="add" class="acc">' + I.plus + 'Ajouter</button><button data-nav="more">' + I.more + 'Plus</button></nav>' +
    '<nav class="ed-blockbar" id="edBlock" hidden></nav>' +
    '<div class="ed-textbar" id="edText" hidden></div>' +
    '<div class="ed-scrim" id="edScrim"></div><section class="ed-sheet" id="edSheet" role="dialog" aria-modal="true"><div class="ed-sheet-h"><b id="edSheetT"></b><button class="ed-ib" id="edSheetX" aria-label="Fermer">' + I.close + '</button></div><div class="ed-sheet-b" id="edSheetB"></div></section>' +
    '<input type="file" id="edFile" accept="image/*" hidden>';
  var canvas = document.getElementById('canvas'), sheet = document.getElementById('edSheet'), sheetB = document.getElementById('edSheetB'), scrim = document.getElementById('edScrim');
  var blockBar = document.getElementById('edBlock'), nav = document.getElementById('edNav'), textBar = document.getElementById('edText');
  document.body.classList.add('ed-on');
  document.getElementById('edName').textContent = ctx.title || 'Ma carte';
  var toast = function (m) { S.toast(canvas, m); };

  // --------------------------------------------------------------- the doc
  function blockById(id) { return (doc.blocks || []).filter(function (b) { return b.id === id; })[0] || null; }
  function indexOf(id) { for (var i = 0; i < doc.blocks.length; i++) if (doc.blocks[i].id === id) return i; return -1; }
  function setPath(o, path, v) {
    var ks = path.split('.'), last = ks.pop(), cur = o;
    ks.forEach(function (k, i) { if (cur[k] == null || typeof cur[k] !== 'object') cur[k] = /^\d+$/.test(ks[i + 1] || last) ? [] : {}; cur = cur[k]; });
    cur[last] = v;
  }
  function snap() { hist.push(JSON.stringify(doc)); if (hist.length > 60) hist.shift(); fut = []; }
  function commit(fn, keepText) { snap(); fn(); changed(); draw(keepText); }
  function changed() { stateBar(); keepDraft(); }
  var draftT;
  function keepDraft() {
    clearTimeout(draftT);
    draftT = setTimeout(function () {
      try { if (dirty()) localStorage.setItem(DRAFT, JSON.stringify({ doc: clean(doc), at: Date.now(), base: savedAt })); else localStorage.removeItem(DRAFT); } catch (e) {}
    }, 500);
  }
  // The same document whatever the order of its keys (Postgres keeps a
  // jsonb's keys in its own order).
  function canon(x) {
    if (Array.isArray(x)) return '[' + x.map(canon).join(',') + ']';
    if (x && typeof x === 'object') return '{' + Object.keys(x).sort().filter(function (k) { return x[k] !== undefined; }).map(function (k) { return JSON.stringify(k) + ':' + canon(x[k]); }).join(',') + '}';
    return JSON.stringify(x);
  }
  function dirty() { return canon(clean(doc)) !== savedJson; }
  function stateBar() {
    document.getElementById('edUndo').disabled = !hist.length;
    document.getElementById('edRedo').disabled = !fut.length;
    var d = dirty(), sv = document.getElementById('edSave');
    sv.classList.toggle('dirty', d);
    document.getElementById('edState').textContent = d ? 'Non enregistrée' : (savedAt ? 'Enregistrée à ' + new Date(savedAt).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' }) : 'Studio');
  }
  // What goes to the server: no picture still on the phone (local), nothing empty.
  function clean(d) {
    return JSON.parse(JSON.stringify(d, function (k, v) { return k === 'local' ? undefined : v; }));
  }
  function pending(d) {
    var found = false;
    JSON.stringify(d, function (k, v) { if (v && typeof v === 'object' && v.local && !v.key) found = true; return v; });
    return found;
  }

  // ------------------------------------------------------------- drawing
  var wired = null;   // what the last drawing wired (its countdown stops with it)
  function draw(keepText) {
    var f = S.facts(ctx), html = '', list = doc.blocks || [];
    if (wired) clearInterval(wired._cd);
    S.applyTheme(canvas, doc.theme);
    if (preview) {
      // the guests' page: drawn as theirs, its buttons alive, nothing sent
      var look = Object.assign({}, ctx, { editing: false, demo: true, look: true });
      canvas.innerHTML = '<main class="st-card">' + S.render(doc, look) + '</main>';
      wired = canvas.firstChild; S.wire(wired, look, doc); S.motion(canvas);
      return;
    }
    list.forEach(function (b, i) {
      html += '<div class="ed-ins"><button type="button" data-ins="' + i + '" aria-label="Ajouter un bloc ici">+</button></div>';
      html += S.renderBlock(b, ctx, f);
    });
    html += '<div class="ed-ins"><button type="button" data-ins="' + list.length + '" aria-label="Ajouter un bloc à la fin">+</button></div>';
    canvas.innerHTML = '<main class="st-card">' + html + '</main>';
    Array.prototype.forEach.call(canvas.querySelectorAll('[data-f]'), function (el) {
      if (el.closest('button, a')) return;   // a button's label: in the block's settings
      el.setAttribute('contenteditable', 'true'); el.setAttribute('spellcheck', 'true');
    });
    wired = canvas; S.wire(canvas, ctx, doc);
    if (sel && !blockById(sel)) sel = null;
    markSel();
    if (!keepText) closeText();
    else if (textSel) { var el = fieldEl(textSel); if (el) el.classList.add('ed-tsel'); }
  }
  function fieldEl(ts) { var bl = canvas.querySelector('[data-bid="' + ts.bid + '"]'); return bl && bl.querySelector('[data-f="' + ts.path + '"]'); }
  function markSel() {
    Array.prototype.forEach.call(canvas.querySelectorAll('.ed-sel'), function (x) { x.classList.remove('ed-sel'); });
    var el = sel && canvas.querySelector('[data-bid="' + sel + '"]');
    if (el) el.classList.add('ed-sel');
    drawBlockBar();
  }

  // ----------------------------------------------------- the selected block
  function select(id, scroll) {
    sel = id; markSel();
    if (scroll) { var el = canvas.querySelector('[data-bid="' + id + '"]'); if (el) el.scrollIntoView({ behavior: 'smooth', block: 'center' }); }
  }
  function drawBlockBar() {
    var b = sel && blockById(sel);
    nav.hidden = !!b; blockBar.hidden = !b;
    if (!b) return;
    var i = indexOf(b.id), def = S.BLOCKS[b.type];
    blockBar.innerHTML = '<span class="ed-bb-name">' + esc(def ? def.name : b.type) + '</span>' +
      '<button data-bb="settings">' + I.gear + 'Réglages</button><button data-bb="up"' + (i <= 0 ? ' disabled' : '') + '>' + I.up + 'Monter</button>' +
      '<button data-bb="down"' + (i >= doc.blocks.length - 1 ? ' disabled' : '') + '>' + I.down + 'Descendre</button><button data-bb="dup">' + I.copy + 'Dupliquer</button>' +
      '<button data-bb="hide">' + I.hide + (b.hidden ? 'Afficher' : 'Masquer') + '</button><button data-bb="del" class="danger">' + I.trash + 'Supprimer</button><button data-bb="close">' + I.close + 'Fermer</button>';
  }
  blockBar.addEventListener('click', function (e) {
    var bt = e.target.closest('[data-bb]'); if (!bt || bt.disabled) return;
    var a = bt.getAttribute('data-bb'), b = blockById(sel); if (!b) return;
    var i = indexOf(b.id);
    if (a === 'settings') return openSettings(b.id);
    if (a === 'close') { sel = null; markSel(); return; }
    if (a === 'up' || a === 'down') { var j = a === 'up' ? i - 1 : i + 1; commit(function () { doc.blocks.splice(j, 0, doc.blocks.splice(i, 1)[0]); }); select(b.id, true); return; }
    if (a === 'dup') { var c = JSON.parse(JSON.stringify(b)); c.id = U.uid(); commit(function () { doc.blocks.splice(i + 1, 0, c); }); select(c.id, true); toast('Bloc dupliqué.'); return; }
    if (a === 'hide') { commit(function () { b.hidden = !b.hidden; }); toast(b.hidden ? 'Masqué : vos invités ne le voient pas.' : 'Visible pour vos invités.'); return; }
    if (a === 'del') { commit(function () { doc.blocks.splice(i, 1); }); sel = null; markSel(); toast('Bloc supprimé. « Annuler » le remet.'); }
  });

  // ------------------------------------------------- the card, touched
  canvas.addEventListener('click', function (e) {
    if (preview) return;
    var ins = e.target.closest('[data-ins]');
    if (ins) { inserting = +ins.getAttribute('data-ins'); openLibrary(); return; }
    var blockEl = e.target.closest('[data-bid]'), b = blockEl && blockById(blockEl.getAttribute('data-bid'));
    var add = e.target.closest('.st-add-item');
    if (add && b) { e.preventDefault(); addItem(b, add.getAttribute('data-add')); return; }
    var ph = e.target.closest('[data-p]');
    if (ph && b && !e.target.closest('[data-f]')) { select(b.id); openPhoto(b.id, ph.getAttribute('data-p')); return; }
    if (e.target.closest('a, button, summary')) e.preventDefault();   // nothing opens, nothing folds
    if (e.target.closest('[data-f]')) { if (b && sel !== b.id) select(b.id); return; }
    if (b) select(b.id);   // a second tap keeps it chosen; « Fermer » lets it go
    else if (sel) { sel = null; markSel(); }
  });
  canvas.addEventListener('submit', function (e) { e.preventDefault(); });
  // writing in place
  var typing = null;
  canvas.addEventListener('focusin', function (e) {
    var el = e.target.closest && e.target.closest('[data-f]'); if (!el) return;
    var bl = el.closest('[data-bid]'); if (!bl) return;
    typing = null;
    document.body.classList.add('ed-typing');   // the keyboard takes the bottom: the bars step aside
    openText({ bid: bl.getAttribute('data-bid'), path: el.getAttribute('data-f') });
  });
  canvas.addEventListener('focusout', function (e) {
    if (e.target.closest && e.target.closest('[data-f]')) document.body.classList.remove('ed-typing');
  });
  canvas.addEventListener('input', function (e) {
    var el = e.target.closest && e.target.closest('[data-f]'); if (!el) return;
    var bl = el.closest('[data-bid]'), b = bl && blockById(bl.getAttribute('data-bid')); if (!b) return;
    var path = el.getAttribute('data-f'), multi = el.hasAttribute('data-multi');
    var v = multi ? el.innerText.replace(/ /g, ' ').replace(/\n{3,}/g, '\n\n').replace(/^\s+|\s+$/g, '') : el.textContent.replace(/\s+/g, ' ').trim();
    if (typing !== el) { snap(); typing = el; }
    b.props = b.props || {};
    setPath(b.props, path, v.slice(0, 4000));
    changed();
  });
  canvas.addEventListener('keydown', function (e) {
    var el = e.target.closest && e.target.closest('[data-f]'); if (!el) return;
    if (e.key === 'Enter' && !el.hasAttribute('data-multi')) { e.preventDefault(); el.blur(); }
    // a question's words sit in a <summary>, whose space would fold it
    if (e.key === ' ' && el.closest('summary')) { e.preventDefault(); document.execCommand('insertText', false, ' '); }
  });
  canvas.addEventListener('paste', function (e) {
    var el = e.target.closest && e.target.closest('[data-f]'); if (!el) return;
    e.preventDefault();
    var t = ((e.clipboardData || window.clipboardData).getData('text') || '');
    if (!el.hasAttribute('data-multi')) t = t.replace(/\s+/g, ' ');
    document.execCommand('insertText', false, t);
  });
  function addItem(b, key) {
    var blank = {
      programme: { items: { time: '', title: '', detail: '', icon: 'star' } }, infos: { items: { icon: 'info', title: '', text: '' } },
      contribution: { lines: { label: '', value: '' } }, faq: { items: { q: '', a: '' } }, menu: { items: { title: '', text: '' } },
      story: { items: { date: '', title: '', text: '' } }, gallery: { photos: null }
    }[b.type];
    if (b.type === 'gallery') { openPhoto(b.id, 'photos.' + ((b.props.photos || []).length)); return; }
    var item = blank && blank[key];
    if (!item) return;
    commit(function () { b.props[key] = (b.props[key] || []).concat([JSON.parse(JSON.stringify(item))]); });
    var bl = canvas.querySelector('[data-bid="' + b.id + '"]'), n = b.props[key].length - 1;
    var first = bl && bl.querySelector('[data-i="' + n + '"] [data-f]');
    if (first) { first.focus(); first.scrollIntoView({ block: 'center' }); }
  }

  // ------------------------------------------------------ the text toolbar
  var TSIZES = ['XS', 'S', 'M', 'L', 'XL', 'XXL'];
  function openText(ts) {
    canvas.querySelectorAll('.ed-tsel').forEach(function (x) { x.classList.remove('ed-tsel'); });
    textSel = ts; var b = blockById(ts.bid); if (!b) return;
    var f = (b.style && b.style.f && b.style.f[S.fkey(ts.path)]) || {};
    var fonts = '<option value="">Police : du thème</option><option value="display"' + (f.ff === 'display' ? ' selected' : '') + '>Titres</option><option value="body"' + (f.ff === 'body' ? ' selected' : '') + '>Texte</option><option value="script"' + (f.ff === 'script' ? ' selected' : '') + '>Écriture</option>' +
      Object.keys(S.FONTS).map(function (id) { return '<option value="' + id + '"' + (f.ff === id ? ' selected' : '') + '>' + esc(S.FONT_NAMES[id] || id) + '</option>'; }).join('');
    var cols = [['', 'Couleur : du bloc'], ['accent', 'Accent'], ['ink', 'Texte'], ['paper', 'Papier'], ['white', 'Blanc'], ['black', 'Noir']];
    textBar.innerHTML = '<button data-t="size" data-d="-1" aria-label="Plus petit">A−</button><button data-t="size" data-d="1" aria-label="Plus grand">A+</button><span class="sep"></span>' +
      '<button data-t="b" aria-pressed="' + !!f.b + '"><b>G</b></button><button data-t="i" aria-pressed="' + !!f.i + '"><i>I</i></button><button data-t="u" aria-pressed="' + !!f.u + '">AA</button>' +
      '<button data-t="ls" aria-pressed="' + !!f.ls + '">A·B</button>' +
      '<button data-t="a" aria-pressed="' + !!f.a + '" aria-label="Alignement : ' + ({ l: 'à gauche', c: 'centré', r: 'à droite' }[f.a] || 'celui du bloc') + '">' + ({ l: '⇤', c: '↔', r: '⇥' }[f.a] || '≡') + '</button><span class="sep"></span>' +
      '<select data-t="c" aria-label="Couleur">' + cols.map(function (c) { return '<option value="' + c[0] + '"' + ((f.c || '') === c[0] ? ' selected' : '') + '>' + c[1] + '</option>'; }).join('') + (U.isHex(f.c) ? '<option value="' + f.c + '" selected>Ma couleur</option>' : '') + '<option value="pick">Autre couleur…</option></select>' +
      '<select data-t="ff" aria-label="Police">' + fonts + '</select><button data-t="reset">Par défaut</button><button data-t="ok" aria-label="Terminé">OK</button>';
    textBar.hidden = false;
  }
  function closeText() { textSel = null; textBar.hidden = true; canvas.querySelectorAll('.ed-tsel').forEach(function (x) { x.classList.remove('ed-tsel'); }); }
  textBar.addEventListener('pointerdown', function (e) { if (e.target.closest('button')) e.preventDefault(); });   // the field keeps the keyboard
  function setFieldStyle(fn) {
    var b = textSel && blockById(textSel.bid); if (!b) return;
    snap();
    b.style = b.style || {}; b.style.f = b.style.f || {};
    var k = S.fkey(textSel.path), f = b.style.f[k] || {};
    fn(f);
    Object.keys(f).forEach(function (x) { if (f[x] === '' || f[x] === 0 || f[x] === false || f[x] == null) delete f[x]; });
    if (Object.keys(f).length) b.style.f[k] = f; else delete b.style.f[k];
    if (!Object.keys(b.style.f).length) delete b.style.f;
    var bl = canvas.querySelector('[data-bid="' + b.id + '"]');
    Array.prototype.forEach.call(bl ? bl.querySelectorAll('[data-f]') : [], function (el) { if (S.fkey(el.getAttribute('data-f')) === k) el.setAttribute('style', S.fieldStyle(b, el.getAttribute('data-f'))); });
    changed(); openText(textSel);
  }
  textBar.addEventListener('click', function (e) {
    var bt = e.target.closest('button[data-t]'); if (!bt) return;
    var t = bt.getAttribute('data-t');
    if (t === 'ok') { if (document.activeElement && document.activeElement.blur) document.activeElement.blur(); closeText(); return; }
    setFieldStyle(function (f) {
      if (t === 'size') { var i = TSIZES.indexOf(f.s || 'M') + (+bt.getAttribute('data-d')); f.s = TSIZES[Math.max(0, Math.min(TSIZES.length - 1, i))]; if (f.s === 'M') delete f.s; }
      else if (t === 'reset') { Object.keys(f).forEach(function (x) { delete f[x]; }); }
      else if (t === 'a') f.a = { '': 'l', l: 'c', c: 'r', r: '' }[f.a || ''];
      else f[t] = f[t] ? 0 : 1;
    });
  });
  textBar.addEventListener('change', function (e) {
    var s = e.target.closest('select[data-t]'); if (!s) return;
    var t = s.getAttribute('data-t'), v = s.value;
    if (t === 'c' && v === 'pick') {
      var inp = document.createElement('input'); inp.type = 'color'; inp.value = '#c2185b';
      inp.addEventListener('change', function () { setFieldStyle(function (f) { f.c = inp.value.toLowerCase(); }); });
      inp.click(); return;
    }
    setFieldStyle(function (f) { f[t] = v; });
  });

  // ----------------------------------------------------------------- sheets
  var sheetClose = null;
  function openSheet(title, html, wire, onClose, half) {
    var top = sheet.classList.contains('open') ? sheetB.scrollTop : 0, same = document.getElementById('edSheetT').textContent === title;
    document.getElementById('edSheetT').textContent = title;
    sheetB.innerHTML = html; sheet.classList.add('open'); scrim.classList.add('on'); document.body.classList.add('ed-sheet-on');
    // half the screen: the card stays in view above, without the scrim
    sheet.classList.toggle('half', !!half); document.body.classList.toggle('ed-half', !!half); scrim.classList.toggle('clear', !!half);
    if (same) sheetB.scrollTop = top;   // redrawn after a choice: where it was
    sheetClose = onClose || null;
    if (wire) wire(sheetB);
  }
  function closeSheet() {
    sheet.classList.remove('open', 'half'); scrim.classList.remove('on', 'clear'); document.body.classList.remove('ed-half', 'ed-sheet-on');
    document.getElementById('edSheetT').textContent = '';
    if (sheetClose) { var f = sheetClose; sheetClose = null; f(); }
  }
  // a block brought just under the top bar (a half sheet below it)
  function reveal(id) {
    var el = canvas.querySelector('[data-bid="' + id + '"]'); if (!el) return;
    window.scrollTo({ top: Math.max(0, el.getBoundingClientRect().top + window.scrollY - 70), behavior: 'smooth' });
  }
  document.getElementById('edSheetX').onclick = closeSheet; scrim.onclick = closeSheet;
  function chips(name, list, cur) { return '<div class="ed-row">' + list.map(function (x) { return '<button type="button" class="ed-chip" data-' + name + '="' + esc(x[0]) + '" aria-pressed="' + (String(cur) === String(x[0])) + '">' + esc(x[1]) + '</button>'; }).join('') + '</div>'; }

  // the library: a block to add
  function openLibrary() {
    var groups = {};
    Object.keys(S.BLOCKS).forEach(function (t) { var d = S.BLOCKS[t]; (groups[d.group] = groups[d.group] || []).push(t); });
    var order = ['Essentiels', 'Le jour', 'Les invités', 'Photos', 'Textes', 'Mise en page'];
    openSheet('Ajouter un bloc', order.filter(function (g) { return groups[g]; }).map(function (g) {
      return '<p class="ed-lab">' + esc(g) + '</p><div class="ed-lib">' + groups[g].map(function (t) {
        var d = S.BLOCKS[t];
        return '<button type="button" data-type="' + t + '"><svg viewBox="0 0 24 24">' + (S.ICONS[d.icon] || S.ICONS.star) + '</svg><b>' + esc(d.name) + '</b><span>' + esc(d.desc) + '</span></button>';
      }).join('') + '</div>';
    }).join(''), function (box) {
      box.addEventListener('click', function (e) {
        var bt = e.target.closest('[data-type]'); if (!bt) return;
        var t = bt.getAttribute('data-type'), d = S.BLOCKS[t], b = { id: U.uid(), type: t, variant: d.variants[0][0], props: d.make(ctx) };
        var at = inserting != null ? inserting : (sel ? indexOf(sel) + 1 : Math.max(0, doc.blocks.length - (doc.blocks.length && doc.blocks[doc.blocks.length - 1].type === 'footer' ? 1 : 0)));
        inserting = null;
        commit(function () { doc.blocks.splice(at, 0, b); });
        closeSheet(); select(b.id, true); toast(d.name + ' ajouté. Touchez un texte pour l’écrire.');
      });
    }, function () { inserting = null; });
  }

  // the block's settings
  var ICON_LIST = ['star', 'heart', 'rings', 'glass', 'food', 'cake', 'party', 'music', 'mic', 'camera', 'pin', 'clock', 'calendar', 'dress', 'gift', 'car', 'bed', 'child', 'phone', 'dove', 'money', 'leaf', 'info'];
  var ICON_NAMES = { star: 'Étoile', heart: 'Cœur', rings: 'Alliances', glass: 'Verre', food: 'Repas', cake: 'Gâteau', party: 'Fête', music: 'Musique', mic: 'Micro', camera: 'Photo', pin: 'Lieu', clock: 'Heure', calendar: 'Date', dress: 'Tenue', gift: 'Cadeau', car: 'Voiture', bed: 'Hébergement', child: 'Enfants', phone: 'Téléphone', dove: 'Colombe', money: 'Argent', leaf: 'Feuille', info: 'Info' };
  function iconSelect(cur, attr) { return '<select ' + attr + '>' + ICON_LIST.map(function (i) { return '<option value="' + i + '"' + (i === cur ? ' selected' : '') + '>' + ICON_NAMES[i] + '</option>'; }).join('') + '</select>'; }
  var LISTS = { programme: ['items', 'title', true], infos: ['items', 'title', true], contribution: ['lines', 'label'], faq: ['items', 'q'], menu: ['items', 'title'], story: ['items', 'title'], gallery: ['photos', null] };
  function openSettings(id) {
    var b = blockById(id); if (!b) return;
    var d = S.BLOCKS[b.type], p = b.props || {}, st = b.style || {}, h = '';
    if (d.variants.length > 1) h += '<p class="ed-lab">Présentation</p>' + chips('var', d.variants, b.variant || d.variants[0][0]);
    // what is not written on the card itself
    var field = function (key, label, type, ph) { return '<label class="ed-field">' + esc(label) + '<input data-prop="' + key + '" type="' + (type || 'text') + '" value="' + esc(p[key] || '') + '" placeholder="' + esc(ph || '') + '"></label>'; };
    var check = function (key, label, dflt) { var on = p[key] == null ? dflt : !!p[key]; return '<label class="ed-check"><input type="checkbox" data-bool="' + key + '"' + (on ? ' checked' : '') + '>' + esc(label) + '</label>'; };
    var photoBtn = function (path, label) { return '<button type="button" class="ed-chip" data-photo="' + path + '">' + esc(label) + '</button>'; };
    if (b.type === 'cover') h += '<p class="ed-lab">La photo et la date</p><div class="ed-row">' + photoBtn('photo', 'Changer la photo') + '</div>' + check('showDate', 'Afficher la date et l’heure', true) + check('showPlace', 'Afficher le lieu', true) +
      field('dateText', 'Date écrite autrement (facultatif)', 'text', 'Ex. : Le premier samedi de mai') + field('placeText', 'Lieu écrit autrement (facultatif)', 'text', ctx.place);
    if (b.type === 'photo' || b.type === 'free') h += '<p class="ed-lab">La photo</p><div class="ed-row">' + photoBtn('photo', 'Changer la photo') + '</div>';
    if (b.type === 'free') h += field('button', 'Texte du bouton (facultatif)', 'text', 'Voir le plan') + field('href', 'Lien du bouton', 'url', 'https://…');
    if (b.type === 'button') h += field('label', 'Texte du bouton') + field('href', 'Lien', 'url', 'https://…');
    if (b.type === 'calendar') h += field('label', 'Texte du bouton');
    if (b.type === 'tickets') h += field('label', 'Texte du bouton');
    if (b.type === 'place') h += field('href', 'Lien de la carte (facultatif)', 'url', 'https://maps.app.goo.gl/…');
    if (b.type === 'countdown') h += field('doneText', 'Le jour venu, écrire', 'text', 'C’est aujourd’hui !');
    if (b.type === 'video') h += field('url', 'Lien YouTube', 'url', 'https://youtu.be/…');
    if (b.type === 'music') h += field('url', 'Lien du fichier audio (https)', 'url', 'https://…/chanson.mp3');
    if (b.type === 'programme') h += check('showTimes', 'Afficher les horaires', true);
    if (b.type === 'rsvp') h += field('yes', 'Bouton « oui »', 'text', 'Je viens') + field('no', 'Bouton « non »', 'text', 'Je ne peux pas') + check('askPhone', 'Demander le WhatsApp pour le rappel de la veille', true) + check('pass', 'Carte d’invité (QR) après « Je viens »', false) +
      (ctx.rsvp_on === false ? '<p class="ed-lab">Les réponses sont fermées dans Marakaj : vos invités voient « Les réponses sont fermées ».</p>' : '');
    if (b.type === 'dresscode') h += '<p class="ed-lab">Les couleurs</p><div class="ed-row">' + (p.colors || []).map(function (c, i) { return '<input type="color" data-dc="' + i + '" value="' + esc(c) + '"><button type="button" class="ed-chip" data-dcdel="' + i + '">✕</button>'; }).join('') + '<button type="button" class="ed-chip" data-dcadd>+ Une couleur</button></div>';
    var L = LISTS[b.type];
    if (L) {
      var arr = p[L[0]] || [];
      h += '<p class="ed-lab">' + (b.type === 'gallery' ? 'Les photos' : 'Les éléments') + ' — l’ordre, les icônes</p><div class="ed-list">' + arr.map(function (it, i) {
        var label = b.type === 'gallery' ? 'Photo ' + (i + 1) : ((it && it[L[1]]) || '(vide)');
        return '<div class="ed-list-it">' + (b.type === 'gallery' ? '<button type="button" data-photo="photos.' + i + '" style="width:42px;background:#333 url(\'' + esc(S.picSrc(it, ctx, 200)) + '\') center/cover"></button>' : '') +
          '<span>' + esc(label) + '</span>' + (L[2] ? iconSelect(it && it.icon, 'data-icon="' + i + '"') : '') +
          '<button type="button" data-mv="' + i + '" data-d="-1"' + (i ? '' : ' disabled') + '>↑</button><button type="button" data-mv="' + i + '" data-d="1"' + (i < arr.length - 1 ? '' : ' disabled') + '>↓</button><button type="button" data-rm="' + i + '">✕</button></div>';
      }).join('') + '</div><div class="ed-row" style="margin-top:8px"><button type="button" class="ed-chip" data-additem="' + L[0] + '">+ Ajouter</button></div>';
      if (b.type === 'infos') h += '<p class="ed-lab">Un lien sur un élément (facultatif)</p>' + arr.map(function (it, i) { return '<label class="ed-field">' + esc((it && it.title) || 'Élément ' + (i + 1)) + '<input data-ihref="' + i + '" type="url" placeholder="https://…" value="' + esc((it && it.href) || '') + '"></label>'; }).join('');
    }
    // the look of the block
    var bg = st.bg || '', bgs = [['', 'Du modèle'], ['paper', 'Papier'], ['soft', 'Doux'], ['accent', 'Accent'], ['back', 'Fond de page'], ['ink', 'Sombre'], ['none', 'Transparent'], ['custom', 'Couleur…'], ['photo', 'Photo…']];
    h += '<p class="ed-lab">Fond du bloc</p>' + chips('bg', bgs, U.isHex(bg) ? 'custom' : bg) +
      (U.isHex(bg) ? '<div class="ed-row" style="margin-top:8px"><input type="color" data-bgc value="' + bg + '"></div>' : '') +
      (bg === 'photo' ? '<div class="ed-row" style="margin-top:8px">' + photoBtn('style.bgPhoto', 'Choisir la photo de fond') + '</div><label class="ed-field">Voile sur la photo<input class="ed-range" type="range" min="0" max="85" data-dim value="' + Math.round((st.dim != null ? st.dim : 0.45) * 100) + '"></label>' : '');
    h += '<p class="ed-lab">Alignement</p>' + chips('al', [['', 'Du modèle'], ['left', 'À gauche'], ['center', 'Centré'], ['right', 'À droite']], st.align || '') +
      '<p class="ed-lab">Espace autour</p>' + chips('pad', [['S', 'Serré'], ['', 'Normal'], ['L', 'Large']], st.pad || '') +
      '<p class="ed-lab">Taille des textes</p>' + chips('size', [['S', 'Petite'], ['', 'Normale'], ['L', 'Grande'], ['XL', 'Très grande']], st.size || '') +
      '<p class="ed-lab">Ornement en haut</p>' + chips('sep', [['', 'Aucun'], ['fleur', 'Fleur'], ['ligne', 'Ligne'], ['vague', 'Vague'], ['points', 'Points'], ['coeur', 'Cœur'], ['wax', 'Wax']], st.sep || '') +
      '<label class="ed-check"><input type="checkbox" data-motif' + (st.motif ? ' checked' : '') + '>Motif du thème en fond</label>' +
      '<p class="ed-lab">Ce bloc</p><div class="ed-row"><button type="button" class="ed-chip" data-act="dup">Dupliquer</button><button type="button" class="ed-chip" data-act="hide">' + (b.hidden ? 'Afficher' : 'Masquer') + '</button><button type="button" class="ed-chip danger" data-act="del">Supprimer</button></div>';
    var fresh = !sheet.classList.contains('open');
    openSheet(d.name, h, function (box) { wireSettings(box, b.id); }, null, true);
    if (fresh) reveal(b.id);
  }
  // A link as the server keeps it (171: https, tel or mailto): « www.… » and
  // « http:// » made https, a phone number made tel:. '' for nothing, null
  // for a link that cannot serve.
  function link(raw) {
    var v = String(raw || '').trim();
    if (!v) return '';
    if (/^http:\/\//i.test(v)) v = 'https://' + v.slice(7);
    else if (/^\+?[\d\s.-]{6,}$/.test(v)) v = 'tel:' + v.replace(/[\s.-]/g, '');
    else if (!/^(https:\/\/|tel:|mailto:)/i.test(v) && /^[\w-]+(\.[\w-]+)+([/?#].*)?$/.test(v)) v = 'https://' + v;
    return /^(https:\/\/|tel:|mailto:)[^\s<>"'`]+$/.test(v) ? v : null;
  }
  function wireSettings(box, id) {
    var b = function () { return blockById(id); };
    var re = function () { openSettings(id); };
    box.addEventListener('click', function (e) {
      var t = e.target.closest('button'); if (!t) return;
      var bb = b(); if (!bb) return;
      if (t.hasAttribute('data-var')) { commit(function () { bb.variant = t.getAttribute('data-var'); }); re(); return; }
      if (t.hasAttribute('data-photo')) { openPhoto(id, t.getAttribute('data-photo')); return; }
      if (t.hasAttribute('data-bg')) {
        var v = t.getAttribute('data-bg');
        commit(function () { bb.style = bb.style || {}; if (v === 'custom') bb.style.bg = U.isHex(bb.style.bg) ? bb.style.bg : '#c2185b'; else if (v) bb.style.bg = v; else delete bb.style.bg; });
        re(); if (v === 'photo' && !(bb.style && bb.style.bgPhoto)) openPhoto(id, 'style.bgPhoto'); return;
      }
      ['al:align', 'pad:pad', 'size:size', 'sep:sep'].forEach(function (x) {
        var a = x.split(':');
        if (t.hasAttribute('data-' + a[0])) { var v2 = t.getAttribute('data-' + a[0]); commit(function () { bb.style = bb.style || {}; if (v2) bb.style[a[1]] = v2; else delete bb.style[a[1]]; }); re(); }
      });
      var L = LISTS[bb.type];
      if (L && t.hasAttribute('data-mv')) { var i = +t.getAttribute('data-mv'), j = i + (+t.getAttribute('data-d')); commit(function () { var a2 = bb.props[L[0]]; a2.splice(j, 0, a2.splice(i, 1)[0]); }); re(); return; }
      if (L && t.hasAttribute('data-rm')) { var k = +t.getAttribute('data-rm'); commit(function () { bb.props[L[0]].splice(k, 1); }); re(); return; }
      if (t.hasAttribute('data-additem')) { closeSheet(); addItem(bb, t.getAttribute('data-additem')); return; }
      if (t.hasAttribute('data-dcadd')) { commit(function () { bb.props.colors = (bb.props.colors || []).concat(['#c9a24a']); }); re(); return; }
      if (t.hasAttribute('data-dcdel')) { var m = +t.getAttribute('data-dcdel'); commit(function () { bb.props.colors.splice(m, 1); }); re(); return; }
      var act = t.getAttribute('data-act');
      if (act === 'dup' || act === 'hide' || act === 'del') { closeSheet(); select(id); blockBar.querySelector('[data-bb="' + act + '"]').click(); }
    });
    box.addEventListener('change', function (e) {
      var t = e.target, bb = b(); if (!bb) return;
      if (t.hasAttribute('data-prop')) {
        var isUrl = t.getAttribute('type') === 'url', v = isUrl ? link(t.value) : t.value.trim();
        if (isUrl && v === null) { toast('Ce lien ne peut pas servir : il commence par https://'); t.value = bb.props[t.getAttribute('data-prop')] || ''; return; }
        commit(function () { if (v) bb.props[t.getAttribute('data-prop')] = v.slice(0, 600); else delete bb.props[t.getAttribute('data-prop')]; });
        if (isUrl) t.value = v || '';
        return;
      }
      if (t.hasAttribute('data-bool')) { commit(function () { bb.props[t.getAttribute('data-bool')] = t.checked; }); return; }
      if (t.hasAttribute('data-icon')) { commit(function () { bb.props[LISTS[bb.type][0]][+t.getAttribute('data-icon')].icon = t.value; }); return; }
      if (t.hasAttribute('data-ihref')) {
        var hv = link(t.value);
        if (hv === null) { toast('Ce lien ne peut pas servir : il commence par https://'); return; }
        commit(function () { var it = bb.props.items[+t.getAttribute('data-ihref')]; if (hv) { it.href = hv.slice(0, 600); it.hrefLabel = it.hrefLabel || 'Ouvrir'; } else { delete it.href; delete it.hrefLabel; } });
        t.value = hv || '';
        return;
      }
      if (t.hasAttribute('data-dc')) { commit(function () { bb.props.colors[+t.getAttribute('data-dc')] = t.value.toLowerCase(); }); return; }
      if (t.hasAttribute('data-bgc')) { commit(function () { bb.style.bg = t.value.toLowerCase(); }); return; }
      if (t.hasAttribute('data-motif')) { commit(function () { bb.style = bb.style || {}; if (t.checked) bb.style.motif = true; else delete bb.style.motif; }); return; }
      if (t.hasAttribute('data-dim')) { commit(function () { bb.style.dim = (+t.value) / 100; }); }
    });
  }

  // a picture: upload, the bank, the framing, a filter
  var photoTarget = null;
  function photoAt(b, path) { return path.indexOf('style.') === 0 ? U.get(b.style || {}, path.slice(6)) : U.get(b.props || {}, path); }
  function setPhoto(b, path, v) {
    if (path.indexOf('style.') === 0) { b.style = b.style || {}; if (v) setPath(b.style, path.slice(6), v); else delete b.style[path.slice(6)]; return; }
    var m = /^photos\.(\d+)$/.exec(path);
    if (m && !v) { b.props.photos.splice(+m[1], 1); return; }
    if (m) { b.props.photos = b.props.photos || []; b.props.photos[+m[1]] = v; return; }
    setPath(b.props, path, v);
  }
  function openPhoto(id, path) {
    var b = blockById(id); if (!b) return;
    photoTarget = { id: id, path: path };
    var ph = photoAt(b, path), src = S.picSrc(ph, ctx, 900), pos = ph && Array.isArray(ph.pos) ? ph.pos : [50, 50];
    var h = (src ? '<div class="ed-crop" id="edCrop"><img src="' + esc(src) + '" alt="" style="object-position:' + pos[0] + '% ' + pos[1] + '%"><i style="left:' + pos[0] + '%;top:' + pos[1] + '%"></i></div>' +
      '<p class="ed-lab">Glissez sur la photo pour choisir ce qui reste au centre.</p><label class="ed-field">Zoom<input class="ed-range" type="range" min="100" max="250" id="edZoom" value="' + Math.round(((ph && ph.zoom) || 1) * 100) + '"></label>' +
      '<p class="ed-lab">Filtre</p>' + chips('flt', [['', 'Aucun'], ['nb', 'Noir et blanc'], ['sepia', 'Sépia'], ['chaud', 'Chaud'], ['doux', 'Doux'], ['vif', 'Vif']], (ph && ph.filter) || '') : '') +
      '<p class="ed-lab">' + (src ? 'Remplacer' : 'Choisir une photo') + '</p><div class="ed-row"><button type="button" class="ed-chip" data-up>Depuis le téléphone</button>' + (src ? '<button type="button" class="ed-chip danger" data-rmph>Retirer la photo</button>' : '') + '</div>' +
      '<p class="ed-lab">La banque Marakaj</p><div class="ed-stock">' + S.STOCK.map(function (s) { return '<button type="button" data-stock="' + s + '" style="background-image:url(\'/cartes/img/' + s + '.jpg\')" aria-label="' + s + '"></button>'; }).join('') + '</div>';
    openSheet('Photo', h, function (box) {
      box.addEventListener('click', function (e) {
        var t = e.target.closest('button'); if (!t) return;
        var bb = blockById(id); if (!bb) return;
        if (t.hasAttribute('data-up')) { document.getElementById('edFile').click(); return; }
        if (t.hasAttribute('data-rmph')) { commit(function () { setPhoto(bb, path, null); }); closeSheet(); return; }
        if (t.hasAttribute('data-stock')) { commit(function () { setPhoto(bb, path, { stock: t.getAttribute('data-stock'), pos: [50, 50] }); }); openPhoto(id, path); return; }
        if (t.hasAttribute('data-flt')) { var v = t.getAttribute('data-flt'); commit(function () { var p2 = photoAt(bb, path); if (v) p2.filter = v; else delete p2.filter; }); openPhoto(id, path); }
      });
      var crop = box.querySelector('#edCrop');
      if (crop) {
        var start = null, cur = pos.slice();
        crop.addEventListener('pointerdown', function (e) { start = { x: e.clientX, y: e.clientY, p: cur.slice(), w: crop.clientWidth, h: crop.clientHeight }; try { crop.setPointerCapture(e.pointerId); } catch (x) {} e.preventDefault(); });
        crop.addEventListener('pointermove', function (e) {
          if (!start) return;
          cur = [Math.max(0, Math.min(100, start.p[0] - (e.clientX - start.x) / start.w * 100)), Math.max(0, Math.min(100, start.p[1] - (e.clientY - start.y) / start.h * 100))];
          crop.querySelector('img').style.objectPosition = cur[0] + '% ' + cur[1] + '%'; crop.querySelector('i').style.left = cur[0] + '%'; crop.querySelector('i').style.top = cur[1] + '%';
        });
        var end = function () { if (!start) return; start = null; var bb = blockById(id); commit(function () { photoAt(bb, path).pos = [Math.round(cur[0]), Math.round(cur[1])]; }); };
        crop.addEventListener('pointerup', end); crop.addEventListener('pointercancel', end);
        box.querySelector('#edZoom').addEventListener('change', function (e) { var bb = blockById(id), z = (+e.target.value) / 100; commit(function () { var p2 = photoAt(bb, path); if (z > 1.01) p2.zoom = Math.round(z * 100) / 100; else delete p2.zoom; }); });
      }
    });
  }
  document.getElementById('edFile').addEventListener('change', function (e) {
    var file = e.target.files && e.target.files[0]; e.target.value = '';
    if (!file || !photoTarget) return;
    var tg = photoTarget;
    if (!ctx.uploads || !ctx.edit) { toast('Les photos ne peuvent pas être envoyées d’ici pour le moment.'); return; }
    S.shrink(file, 1800, function (blob) {
      if (!blob) { toast('Cette image ne peut pas être lue.'); return; }
      var local = URL.createObjectURL(blob), b0 = blockById(tg.id);
      commit(function () { setPhoto(b0, tg.path, { local: local, pos: [50, 50] }); });
      closeSheet(); toast('Envoi de la photo…');
      fetch(ctx.uploads + '/v1/events/' + encodeURIComponent(ctx.slug) + '/pictures?modifier=' + encodeURIComponent(ctx.edit), { method: 'POST', headers: { 'Content-Type': 'image/jpeg' }, body: blob })
        .then(function (r) { return r.json().then(function (j) { if (!r.ok || !j || !j.key) throw new Error(j && j.error ? j.error : 'La photo n’est pas passée. Réessayez.'); return j; }, function () { throw new Error('La photo n’est pas passée. Réessayez.'); }); })
        .then(function (j) {
          var b1 = blockById(tg.id), p1 = b1 && photoAt(b1, tg.path);
          if (p1 && p1.local === local) { delete p1.local; p1.key = j.key; changed(); draw(); }
          toast('Photo ajoutée. Touchez-la pour la recadrer.');
        }, function (err) {
          var b1 = blockById(tg.id), p1 = b1 && photoAt(b1, tg.path);
          if (p1 && p1.local === local) { setPhoto(b1, tg.path, null); changed(); draw(); }
          toast(err.message);
        });
    });
  });

  // the theme: colours, fonts, motif, motion, corners
  function openTheme() {
    var th = doc.theme = doc.theme || {}, c = S.colorsOf(th), fo = th.fonts || {};
    var h = '<p class="ed-lab">Palettes</p><div class="ed-swatches">' + S.PALETTES.map(function (p) {
      return '<button type="button" data-pal="' + p.id + '" title="' + esc(p.name) + '" aria-label="' + esc(p.name) + '" aria-pressed="' + (th.preset === p.id) + '" style="background:linear-gradient(135deg,' + p.paper + ' 0 50%,' + p.accent + ' 50% 75%,' + p.back + ' 75%)"></button>';
    }).join('') + '</div>' +
      '<p class="ed-lab">Vos couleurs</p><div class="ed-colors">' + [['back', 'Fond de page'], ['paper', 'Papier'], ['ink', 'Texte'], ['accent', 'Accent'], ['soft', 'Doux'], ['line', 'Lignes']].map(function (x) {
        return '<label><input type="color" data-col="' + x[0] + '" value="' + c[x[0]] + '">' + x[1] + '</label>';
      }).join('') + '</div><div class="ed-row" style="margin-top:10px"><button type="button" class="ed-chip" data-fromphoto>Couleurs depuis ma photo</button></div>' +
      '<p class="ed-lab">Écritures</p><div class="ed-pairs">' + S.PAIRS.map(function (p) {
        var on = fo.display === p.display && fo.body === p.body && fo.script === p.script;
        return '<button type="button" data-pair="' + p.id + '" aria-pressed="' + on + '"><b style="font-family:' + S.FONTS[p.display][0].replace(/"/g, '&quot;') + '">Aa <span style="font-family:' + S.FONTS[p.script][0].replace(/"/g, '&quot;') + ';text-transform:none;letter-spacing:0;font-size:22px;display:inline">Belle</span></b><span>' + esc(p.name) + '</span></button>';
      }).join('') + '</div>' +
      ['display:Titres', 'body:Texte', 'script:Écriture'].map(function (x) {
        var r = x.split(':');
        return '<label class="ed-field">' + r[1] + '<select data-font="' + r[0] + '">' + Object.keys(S.FONTS).map(function (id) { return '<option value="' + id + '"' + (fo[r[0]] === id ? ' selected' : '') + '>' + esc(S.FONT_NAMES[id] || id) + '</option>'; }).join('') + '</select></label>';
      }).join('') +
      '<p class="ed-lab">Motif</p>' + chips('motif', [['', 'Aucun']].concat(Object.keys(S.MOTIFS).map(function (k) { return [k, S.MOTIFS[k].name]; })), th.motif && th.motif.id || '') +
      (th.motif && th.motif.id ? '<label class="ed-field">Intensité<input class="ed-range" type="range" min="4" max="40" data-mo value="' + Math.round((th.motif.opacity != null ? th.motif.opacity : 0.12) * 100) + '"></label><label class="ed-check"><input type="checkbox" data-moall' + (th.motif.all ? ' checked' : '') + '>Sur toute la carte</label>' : '') +
      '<p class="ed-lab">Mouvement</p>' + chips('motion', [['aucune', 'Aucun'], ['douce', 'Doux'], ['vivante', 'Vivant']], th.motion || 'douce') +
      '<p class="ed-lab">Coins</p>' + chips('corners', [['droit', 'Droits'], ['doux', 'Doux'], ['rond', 'Ronds']], th.corners || 'doux') +
      '<p class="ed-lab">Repartir d’un modèle</p><div class="ed-row">' + S.DESIGNS.map(function (d) { return '<button type="button" class="ed-chip" data-design="' + d.id + '">' + esc(d.name) + '</button>'; }).join('') + '</div>';
    openSheet('Thème', h, function (box) {
      box.addEventListener('click', function (e) {
        var t = e.target.closest('button'); if (!t) return;
        th = doc.theme = doc.theme || {};   // the live theme (an undo replaces the document)
        if (t.hasAttribute('data-pal')) { var p = S.PALETTES.filter(function (x) { return x.id === t.getAttribute('data-pal'); })[0]; commit(function () { th.preset = p.id; th.colors = { back: p.back, paper: p.paper, ink: p.ink, accent: p.accent }; }); openTheme(); return; }
        if (t.hasAttribute('data-pair')) { var q = S.PAIRS.filter(function (x) { return x.id === t.getAttribute('data-pair'); })[0]; commit(function () { th.fonts = { display: q.display, body: q.body, script: q.script }; }); openTheme(); return; }
        if (t.hasAttribute('data-motif')) { var m = t.getAttribute('data-motif'); commit(function () { if (m) th.motif = { id: m, opacity: (th.motif && th.motif.opacity) || 0.12, all: th.motif && th.motif.all }; else th.motif = null; }); openTheme(); return; }
        if (t.hasAttribute('data-motion')) { commit(function () { th.motion = t.getAttribute('data-motion'); }); openTheme(); return; }
        if (t.hasAttribute('data-corners')) { commit(function () { th.corners = t.getAttribute('data-corners'); }); openTheme(); return; }
        if (t.hasAttribute('data-fromphoto')) { fromPhoto(); return; }
        if (t.hasAttribute('data-design')) {
          if (!confirm('Repartir du modèle « ' + t.textContent + ' » ? Vos textes et vos photos de ce modèle remplacent la carte (« Annuler » la remet).')) return;
          var nd = S.starter(t.getAttribute('data-design'), ctx);
          commit(function () { doc = nd; }); closeSheet(); toast('Modèle appliqué. « Annuler » remet votre carte.');
        }
      });
      box.addEventListener('input', function (e) { var t = e.target; if (t.hasAttribute('data-col')) { canvas.style.setProperty('--st-' + t.getAttribute('data-col'), t.value); } });
      box.addEventListener('change', function (e) {
        var t = e.target;
        th = doc.theme = doc.theme || {};
        if (t.hasAttribute('data-col')) { commit(function () { th.colors = Object.assign({}, th.colors || {}); th.colors[t.getAttribute('data-col')] = t.value.toLowerCase(); delete th.preset; }); return; }
        if (t.hasAttribute('data-font')) { commit(function () { th.fonts = Object.assign({}, th.fonts || {}); th.fonts[t.getAttribute('data-font')] = t.value; }); return; }
        if (t.hasAttribute('data-mo')) { commit(function () { th.motif.opacity = (+t.value) / 100; }); return; }
        if (t.hasAttribute('data-moall')) { commit(function () { th.motif.all = t.checked; }); }
      });
    }, null, true);
  }
  // Three colours from the cover's photo: the most present light, dark and lively.
  function fromPhoto() {
    var cover = (doc.blocks || []).filter(function (b) { return b.props && b.props.photo && S.picSrc(b.props.photo, ctx, 400); })[0];
    if (!cover) { toast('Ajoutez d’abord une photo de couverture.'); return; }
    var im = new Image(); im.crossOrigin = 'anonymous';
    im.onload = function () {
      try {
        var c = document.createElement('canvas'); c.width = 48; c.height = 60; var g = c.getContext('2d'); g.drawImage(im, 0, 0, 48, 60);
        var d = g.getImageData(0, 0, 48, 60).data, px = [];
        for (var i = 0; i < d.length; i += 4) px.push([d[i], d[i + 1], d[i + 2]]);
        var L = function (p) { return (p[0] * 299 + p[1] * 587 + p[2] * 114) / 255000; }, sat = function (p) { var mx = Math.max.apply(null, p), mn = Math.min.apply(null, p); return mx ? (mx - mn) / mx : 0; };
        var hex = function (p) { return '#' + p.map(function (v) { return ('0' + Math.round(v).toString(16)).slice(-2); }).join(''); };
        var avg = function (l) { var s = [0, 0, 0]; l.forEach(function (p) { s[0] += p[0]; s[1] += p[1]; s[2] += p[2]; }); return l.length ? s.map(function (v) { return v / l.length; }) : null; };
        px.sort(function (a, b) { return L(a) - L(b); });
        var dark = avg(px.slice(0, Math.ceil(px.length * 0.12))), light = avg(px.slice(-Math.ceil(px.length * 0.12)));
        var vivid = avg(px.slice().sort(function (a, b) { return sat(b) - sat(a); }).slice(0, Math.ceil(px.length * 0.08)));
        var paper = U.mix(hex(light), '#ffffff', 0.55), ink = U.mix(hex(dark), '#000000', 0.35), accent = hex(vivid || dark);
        commit(function () { doc.theme.colors = { back: U.mix(hex(dark), '#000000', 0.1), paper: paper, ink: ink, accent: accent }; delete doc.theme.preset; });
        openTheme(); toast('Couleurs prises dans votre photo.');
      } catch (e) { toast('Cette photo ne se laisse pas lire ici.'); }
    };
    im.onerror = function () { toast('Cette photo ne se laisse pas lire ici.'); };
    im.src = S.picSrc(cover.props.photo, ctx, 400);
  }

  // the blocks, as a list
  function openBlocks() {
    var h = '<div class="ed-list ed-blocks">' + doc.blocks.map(function (b, i) {
      var d = S.BLOCKS[b.type], label = (b.props && (b.props.title || b.props.names || b.props.text || b.props.label)) || '';
      return '<div class="ed-list-it"><span data-go="' + b.id + '">' + esc(d ? d.name : b.type) + (b.hidden ? ' · masqué' : '') + '<small>' + esc(String(label).slice(0, 60)) + '</small></span>' +
        '<button type="button" data-bmv="' + i + '" data-d="-1"' + (i ? '' : ' disabled') + '>↑</button><button type="button" data-bmv="' + i + '" data-d="1"' + (i < doc.blocks.length - 1 ? '' : ' disabled') + '>↓</button>' +
        '<button type="button" data-bhide="' + i + '">' + (b.hidden ? '◌' : '●') + '</button></div>';
    }).join('') + '</div><div class="ed-row" style="margin-top:10px"><button type="button" class="ed-chip" data-addblock>+ Ajouter un bloc</button></div>';
    openSheet('Les blocs de la carte', h, function (box) {
      box.addEventListener('click', function (e) {
        var go = e.target.closest('[data-go]');
        if (go) { closeSheet(); select(go.getAttribute('data-go'), true); return; }
        var t = e.target.closest('button'); if (!t || t.disabled) return;
        if (t.hasAttribute('data-addblock')) { closeSheet(); openLibrary(); return; }
        if (t.hasAttribute('data-bmv')) { var i = +t.getAttribute('data-bmv'), j = i + (+t.getAttribute('data-d')); commit(function () { doc.blocks.splice(j, 0, doc.blocks.splice(i, 1)[0]); }); openBlocks(); return; }
        if (t.hasAttribute('data-bhide')) { var k = +t.getAttribute('data-bhide'); commit(function () { doc.blocks[k].hidden = !doc.blocks[k].hidden; }); openBlocks(); }
      });
    });
  }

  // more: versions, sharing, the classic card
  function openMore() {
    var link = location.origin + '/e/' + encodeURIComponent(ctx.slug || '');
    var h = '<p class="ed-lab">Partager</p><div class="ed-row"><button type="button" class="ed-chip" data-share="copy">Copier le lien</button><a class="ed-chip" style="display:inline-flex;align-items:center;text-decoration:none" target="_blank" rel="noopener" href="https://wa.me/?text=' + encodeURIComponent((ctx.title || 'Invitation') + ' : ' + link) + '">WhatsApp</a></div>' +
      '<p class="ed-lab">Versions enregistrées</p><div class="ed-list ed-vers" id="edVers"><p class="ed-lab">Chargement…</p></div>' +
      '<p class="ed-lab">La carte classique</p><p style="margin:0 0 10px;font:400 13px/1.45 var(--ed-font);color:var(--ed-mute)">Votre carte d’avant Studio est gardée. Y revenir remet l’ancienne carte pour vos invités ; vos versions Studio restent ici.</p>' +
      '<div class="ed-row"><button type="button" class="ed-chip danger" data-classic>Revenir à la carte classique</button></div>';
    openSheet('Plus', h, function (box) {
      box.addEventListener('click', function (e) {
        var t = e.target.closest('button'); if (!t) return;
        if (t.getAttribute('data-share') === 'copy') { (navigator.clipboard ? navigator.clipboard.writeText(link) : Promise.reject()).then(function () { toast('Lien copié.'); }, function () { toast(link); }); return; }
        if (t.hasAttribute('data-restore')) {
          if (!confirm('Remettre cette version ? Elle devient la carte de vos invités.')) return;
          S.api(ctx, 'event_doc_restore', { p_slug: ctx.slug, p_edit: ctx.edit, p_version: t.getAttribute('data-restore') }).then(function (r) {
            snap(); doc = r.doc; savedJson = canon(clean(doc)); savedAt = r.saved_at; changed(); draw(); closeSheet(); toast('Version remise.');
          }, function (err) { toast(err.message); });
          return;
        }
        if (t.hasAttribute('data-classic')) {
          if (!confirm('Revenir à la carte classique ? Vos invités verront à nouveau l’ancienne carte.')) return;
          S.api(ctx, 'event_doc_clear', { p_slug: ctx.slug, p_edit: ctx.edit }).then(function () {
            try { localStorage.removeItem(DRAFT); } catch (e2) {}
            savedJson = canon(clean(doc)); location.href = '/e/' + encodeURIComponent(ctx.slug) + '?modifier=' + encodeURIComponent(ctx.edit) + '&studio=non';
          }, function (err) { toast(err.message); });
        }
      });
      S.api(ctx, 'event_doc_versions', { p_slug: ctx.slug, p_edit: ctx.edit }).then(function (l) {
        var box2 = document.getElementById('edVers'); if (!box2) return;
        box2.innerHTML = (Array.isArray(l) && l.length) ? l.map(function (v) {
          var d = new Date(v.saved_at);
          return '<div class="ed-list-it"><span>' + esc(d.toLocaleDateString('fr-FR', { day: 'numeric', month: 'long' }) + ' à ' + d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })) +
            '<small>' + v.blocks + ' blocs' + (v.note === 'restore' ? ' · remise' : v.note === 'convert' ? ' · première' : '') + '</small></span><button type="button" data-restore="' + esc(v.id) + '" style="width:auto;padding:0 10px">Remettre</button></div>';
        }).join('') : '<p class="ed-lab">Aucune version enregistrée pour le moment.</p>';
      }, function () { var box2 = document.getElementById('edVers'); if (box2) box2.innerHTML = '<p class="ed-lab">Les versions ne se chargent pas pour le moment.</p>'; });
    });
  }

  nav.addEventListener('click', function (e) {
    var b = e.target.closest('[data-nav]'); if (!b) return;
    var n = b.getAttribute('data-nav');
    if (n === 'blocks') openBlocks(); else if (n === 'theme') openTheme(); else if (n === 'more') openMore(); else { inserting = null; openLibrary(); }
  });

  // ---------------------------------------------------------- the top bar
  document.getElementById('edUndo').onclick = function () { if (!hist.length) return; fut.push(JSON.stringify(doc)); doc = JSON.parse(hist.pop()); changed(); draw(); };
  document.getElementById('edRedo').onclick = function () { if (!fut.length) return; hist.push(JSON.stringify(doc)); doc = JSON.parse(fut.pop()); changed(); draw(); };
  document.getElementById('edPreview').onclick = function () {
    preview = !preview; document.body.classList.toggle('ed-preview', preview); document.body.classList.toggle('ed-on', !preview);
    this.classList.toggle('acc', preview); sel = null; closeSheet(); draw();
    if (preview) toast('Aperçu : la carte comme vos invités la verront.');
  };
  document.getElementById('edClose').onclick = function () {
    if (dirty() && !confirm('Quitter sans enregistrer ? Vos changements restent en brouillon sur ce téléphone.')) return;
    if (history.length > 1) history.back(); else location.href = '/e/' + encodeURIComponent(ctx.slug || '') + (ctx.preview ? '?apercu=' + encodeURIComponent(ctx.preview) : '');
  };
  var saving = false;
  document.getElementById('edSave').onclick = function () {
    if (saving) return;
    if (document.activeElement && document.activeElement.blur) document.activeElement.blur();
    if (pending(doc)) { toast('Une photo est encore en cours d’envoi : un instant.'); return; }
    var body = clean(doc), btn = this;
    saving = true; btn.textContent = 'Envoi…'; clearTimeout(draftT);
    S.api(ctx, 'event_doc_save', { p_slug: ctx.slug, p_edit: ctx.edit, p_doc: body, p_note: converted && !savedAt ? 'convert' : 'save' }).then(function (r) {
      saving = false; btn.textContent = 'Enregistrer';
      savedJson = canon(body); savedAt = r && r.saved_at || new Date().toISOString(); converted = false;
      try { localStorage.removeItem(DRAFT); } catch (e) {}
      stateBar(); toast('Carte enregistrée. Vos invités la voient ainsi.');
    }, function (err) { saving = false; btn.textContent = 'Enregistrer'; toast(err.message || 'La carte n’est pas enregistrée. Réessayez.'); });
  };
  window.addEventListener('beforeunload', function (e) { if (doc && dirty()) { e.preventDefault(); e.returnValue = ''; } });
  document.addEventListener('keydown', function (e) {
    if ((e.ctrlKey || e.metaKey) && !e.shiftKey && e.key === 'z' && !(e.target.closest && e.target.closest('[data-f]'))) { e.preventDefault(); document.getElementById('edUndo').click(); }
    if ((e.ctrlKey || e.metaKey) && (e.key === 'y' || (e.shiftKey && e.key === 'Z'))) { e.preventDefault(); document.getElementById('edRedo').click(); }
    if (e.key === 'Escape') { closeSheet(); }
  });

  // ------------------------------------------------------------- opening
  function start(d, fromServer) {
    doc = d; savedJson = fromServer ? canon(clean(d)) : '';
    var draft = null; try { draft = JSON.parse(localStorage.getItem(DRAFT) || 'null'); } catch (e) { draft = null; }
    draw(); stateBar();
    if (draft && draft.doc && canon(draft.doc) !== canon(clean(d)) && (draft.base || null) === (savedAt || null)) {
      var bn = document.createElement('div'); bn.className = 'ed-banner';
      bn.innerHTML = '<p>Vous aviez des changements non enregistrés sur ce téléphone.</p><button class="ed-ib acc" data-k="1">Les reprendre</button><button class="ed-ib" data-k="0">Les oublier</button>';
      document.body.appendChild(bn);
      bn.addEventListener('click', function (e) {
        var b = e.target.closest('[data-k]'); if (!b) return;
        if (b.getAttribute('data-k') === '1') { snap(); doc = draft.doc; changed(); draw(); toast('Brouillon repris. Touchez « Enregistrer » pour le montrer à vos invités.'); }
        else { try { localStorage.removeItem(DRAFT); } catch (e2) {} }
        bn.remove();
      });
    } else if (!fromServer) {
      toast('Votre carte est prête dans Studio. Rien ne change pour vos invités avant « Enregistrer ».');
    }
  }
  if (BOOT.doc && typeof BOOT.doc === 'object' && Array.isArray(BOOT.doc.blocks)) start(BOOT.doc, true);
  else {
    var wait = document.createElement('div'); wait.className = 'ed-wait'; wait.innerHTML = '<div><i></i>Préparation de votre carte dans Studio…</div>';
    document.body.appendChild(wait);
    S.convert(Object.assign({}, BOOT, ctx), function (d) { wait.remove(); converted = true; start(d, false); });
  }
  S.editor = { get doc() { return doc; }, draw: draw, ctx: ctx };
})();
