// Marakaj Studio — the organiser's helpers (173): the poster to share, the
// card checked before it goes out, the phrases to start from, the colours
// read from a photo. Nothing here is saved by itself: each helper hands the
// editor a picture to download or a change to commit.
(function () {
  'use strict';
  var S = window.Studio;

  // ------------------------------------------------------------ the poster
  // A picture of the card for a WhatsApp status, Instagram or a printer:
  // the cover's photo (else the theme's colours), the names, the day, the
  // place, and a QR code that opens the card. 1080×1920 (a status) or
  // 1080×1080 (a post).
  function firstPhoto(doc) {
    var bl = (doc.blocks || []).filter(function (b) { return !b.hidden; });
    var cover = bl.filter(function (b) { return b.type === 'cover'; })[0];
    var found = null;
    var walk = function (v, d) {
      if (found || !v || typeof v !== 'object' || d > 6) return;
      if (!Array.isArray(v) && (v.key || v.stock || v.local)) { found = v; return; }
      (Array.isArray(v) ? v : Object.keys(v).map(function (k) { return v[k]; })).forEach(function (x) { walk(x, d + 1); });
    };
    if (cover) walk(cover, 0);
    bl.forEach(function (b) { if (b !== cover) walk(b, 0); });
    return found;
  }
  S.firstPhoto = firstPhoto;
  function loadImg(src) {
    return new Promise(function (ok) {
      if (!src) { ok(null); return; }
      var i = new Image(); i.crossOrigin = 'anonymous';
      i.onload = function () { ok(i); }; i.onerror = function () { ok(null); };
      i.src = src;
    });
  }
  function cssVar(el, k, d) { var v = el ? getComputedStyle(el).getPropertyValue(k).trim() : ''; return v || d; }
  // the words of a card's text: its line breaks and inline tags as spaces
  // (DOMParser: an inert document — nothing in the text loads or runs)
  function plain(t) { var d = new DOMParser().parseFromString(String(t || '').replace(/<br\s*\/?>/gi, ' ').replace(/<\/(p|div)>/gi, ' '), 'text/html'); return (d.body.textContent || '').replace(/\s+/g, ' ').trim(); }
  S.plainText = plain;
  function wrap(g, text, maxW) {
    var words = plain(text).split(/\s+/), lines = [], line = '';
    words.forEach(function (w) { var t = line ? line + ' ' + w : w; if (g.measureText(t).width > maxW && line) { lines.push(line); line = w; } else line = t; });
    if (line) lines.push(line);
    return lines;
  }
  function qrCanvas(text, size) {
    if (!window.qrcode) return null;
    var q = window.qrcode(0, 'M'); q.addData(text); q.make();
    var n = q.getModuleCount(), c = document.createElement('canvas'), cell = Math.floor(size / n);
    c.width = c.height = cell * n;
    var g = c.getContext('2d'); g.fillStyle = '#fff'; g.fillRect(0, 0, c.width, c.height); g.fillStyle = '#111';
    for (var r = 0; r < n; r++) for (var k = 0; k < n; k++) if (q.isDark(r, k)) g.fillRect(k * cell, r * cell, cell, cell);
    return c;
  }
  function needQr() {
    return new Promise(function (ok) {
      if (window.qrcode) { ok(); return; }
      var s = document.createElement('script'); s.src = 'https://cdnjs.cloudflare.com/ajax/libs/qrcode-generator/1.4.4/qrcode.min.js';
      s.onload = ok; s.onerror = ok; document.head.appendChild(s);
    });
  }
  S.poster = function (doc, ctx, root, shape) {
    var W = 1080, H = shape === 'carre' ? 1080 : 1920;
    var cover = (doc.blocks || []).filter(function (b) { return b.type === 'cover' && !b.hidden; })[0] || { props: {} };
    var p = cover.props || {}, f = S.facts(ctx), link = location.origin + '/e/' + encodeURIComponent(ctx.slug || '');
    var display = cssVar(root, '--st-display', 'Georgia, serif'), body = cssVar(root, '--st-body', 'sans-serif');
    var back = cssVar(root, '--st-back', '#1f2a23'), accent = cssVar(root, '--st-accent', '#c9a45c');
    var ph = firstPhoto(doc);
    return Promise.all([loadImg(ph ? S.picSrc(ph, ctx, 1600) : ''), needQr(), document.fonts && document.fonts.ready]).then(function (r) {
      var img = r[0], c = document.createElement('canvas'); c.width = W; c.height = H;
      var g = c.getContext('2d');
      g.fillStyle = back; g.fillRect(0, 0, W, H);
      var draw = function (useImg) {
        g.fillStyle = back; g.fillRect(0, 0, W, H);
        if (useImg && img) {
          var s = Math.max(W / img.width, H / img.height), w = img.width * s, h = img.height * s;
          var pos = Array.isArray(ph.pos) ? ph.pos : [50, 50];
          g.drawImage(img, (W - w) * pos[0] / 100, (H - h) * pos[1] / 100, w, h);
          var gr = g.createLinearGradient(0, 0, 0, H); gr.addColorStop(0, 'rgba(0,0,0,.25)'); gr.addColorStop(.45, 'rgba(0,0,0,.35)'); gr.addColorStop(1, 'rgba(0,0,0,.78)');
          g.fillStyle = gr; g.fillRect(0, 0, W, H);
        } else {
          g.fillStyle = accent; g.globalAlpha = .18;
          g.beginPath(); g.arc(W * .85, H * .12, W * .42, 0, 7); g.fill();
          g.beginPath(); g.arc(W * .1, H * .9, W * .5, 0, 7); g.fill(); g.globalAlpha = 1;
        }
        g.fillStyle = '#fff'; g.textAlign = 'center'; g.textBaseline = 'alphabetic';
        var y = shape === 'carre' ? 250 : 620;
        if (p.kicker) { g.font = '600 34px ' + body; g.fillText(plain(p.kicker).toUpperCase().split('').join(' '), W / 2, y); y += 40; }
        g.font = '400 132px ' + display;
        var lines = wrap(g, p.names || ctx.title, W - 160).slice(0, 3);
        lines.forEach(function (l) { y += 138; g.fillText(l, W / 2, y); });
        y += 70; g.fillStyle = accent; g.fillRect(W / 2 - 60, y - 24, 120, 3); g.fillStyle = '#fff';
        g.font = '600 40px ' + body;
        if (f.has) { y += 50; g.fillText((f.long + (f.time ? ' · ' + f.time : '')).toUpperCase(), W / 2, y); }
        if (f.place) { y += 58; g.font = 'italic 400 42px ' + body; wrap(g, f.place, W - 200).slice(0, 2).forEach(function (l, i) { g.fillText(l, W / 2, y + i * 52); }); }
        var q = qrCanvas(link, shape === 'carre' ? 200 : 260);
        if (q) {
          var qs = q.width, qx = W / 2 - qs / 2 - 18, qy = H - qs - (shape === 'carre' ? 110 : 190);
          g.fillStyle = '#fff'; g.beginPath(); if (g.roundRect) g.roundRect(qx, qy, qs + 36, qs + 36, 24); else g.rect(qx, qy, qs + 36, qs + 36); g.fill();
          g.drawImage(q, qx + 18, qy + 18);
          g.fillStyle = '#fff'; g.font = '600 30px ' + body; g.fillText('Scannez pour ouvrir l’invitation', W / 2, qy + qs + 36 + 52);
        }
        g.globalAlpha = .7; g.font = '400 24px ' + body; g.fillText('Carte créée avec Marakaj', W / 2, H - 36); g.globalAlpha = 1;
      };
      draw(true);
      // a photo another site will not lend (CORS): the poster without it
      return new Promise(function (ok) {
        var done = function (b) { ok(b); };
        try { c.toBlob(done, 'image/jpeg', 0.9); } catch (e) { draw(false); c.toBlob(done, 'image/jpeg', 0.9); }
      });
    });
  };

  // ------------------------------------------------- « Vérifier ma carte »
  // What a guest would trip on, said plainly, each with the block to open.
  S.checkCard = function (doc, ctx) {
    var out = [], blocks = (doc.blocks || []).filter(function (b) { return !b.hidden; });
    var has = function (t) { return blocks.some(function (b) { return b.type === t; }); };
    var cover = blocks.filter(function (b) { return b.type === 'cover'; })[0];
    if (!cover) out.push({ level: 'warn', text: 'Pas de couverture : vos invités ne voient pas d’abord les noms.' });
    else if (!String((cover.props || {}).names || '').trim()) out.push({ level: 'warn', text: 'La couverture n’a pas de noms.', id: cover.id });
    if (!ctx.date) out.push({ level: 'warn', text: 'La date n’est pas fixée : « Modifier les infos » dans Marakaj.' });
    if (!ctx.place && !has('place')) out.push({ level: 'warn', text: 'Le lieu n’est pas écrit.' });
    var place = blocks.filter(function (b) { return b.type === 'place'; })[0];
    if (place && !(place.props || {}).href) out.push({ level: 'tip', text: '« Le lieu » sans lien Google Maps : l’itinéraire cherchera le nom du lieu.', id: place.id });
    if (!has('rsvp') && !has('tickets') && ctx.rsvp_on !== false) out.push({ level: 'tip', text: 'Pas de bloc « Réponse des invités » : vos invités ne peuvent pas dire s’ils viennent.' });
    var rs = blocks.filter(function (b) { return b.type === 'rsvp'; })[0];
    if (rs && S.rsvpClosed(rs.props)) out.push({ level: 'warn', text: 'La date limite des réponses est passée : le formulaire est fermé.', id: rs.id });
    blocks.forEach(function (b) {
      var p = b.props || {}, d = S.BLOCKS[b.type];
      if ((b.type === 'text' || b.type === 'story') && !String(p.body || '').trim() && !String(p.title || '').trim()) out.push({ level: 'warn', text: 'Un bloc « ' + (d ? d.name : b.type) + ' » est vide.', id: b.id });
      if (b.type === 'programme' && !(p.items || []).length) out.push({ level: 'warn', text: 'Le programme n’a aucune étape.', id: b.id });
      if (b.type === 'gallery' && !(p.photos || []).length) out.push({ level: 'warn', text: 'La galerie n’a pas de photo.', id: b.id });
      if ((b.type === 'video' || b.type === 'music') && !p.url && !p.track) out.push({ level: 'warn', text: 'Le bloc « ' + (d ? d.name : b.type) + ' » n’a rien à jouer.', id: b.id });
      if (b.type === 'button' && !p.href) out.push({ level: 'warn', text: 'Un bouton sans lien.', id: b.id });
      var txt = JSON.stringify(p);
      if (/Vos prénoms|Le lieu<|Titre<|Lorem|XX h|00 00 00 00/.test(txt)) out.push({ level: 'tip', text: 'Un texte d’exemple est resté dans « ' + (d ? d.name : b.type) + ' ».', id: b.id });
      if (S.firstPhoto({ blocks: [b] }) && S.firstPhoto({ blocks: [b] }).local) out.push({ level: 'warn', text: 'Une photo est encore en cours d’envoi.', id: b.id });
    });
    if (blocks.length > 30) out.push({ level: 'tip', text: blocks.length + ' blocs : une carte plus courte se lit jusqu’au bout.' });
    return out;
  };

  // ------------------------------------------------------- the phrases
  // Words to start from, by kind of event; the organiser changes them after.
  S.PHRASES = {
    mariage: [
      'Avec la bénédiction de nos familles, nous avons la joie de vous inviter à notre mariage.',
      'Deux familles, un seul cœur : venez célébrer notre union avec nous.',
      'Votre présence sera le plus beau des cadeaux.',
      'L’amour est patient, l’amour est bon. — 1 Corinthiens 13, 4'
    ],
    dot: [
      'Les anciens ont parlé, les colas ont été acceptées : venez témoigner et bénir notre union.',
      'Nos deux familles s’unissent : votre présence honorera la cérémonie de dot.',
      'Venez manger, danser et bénir avec nous.'
    ],
    anniversaire: [
      'Une année de plus, et toujours autant d’envie de la fêter avec vous !',
      'Venez souffler les bougies avec moi : bonne musique et bon repas garantis.',
      'Pas de cadeau obligatoire : votre présence suffit.'
    ],
    bapteme: [
      'Nous avons la joie de vous inviter au baptême de notre enfant.',
      'Entourez-nous de vos prières et de votre affection en ce jour béni.'
    ],
    naissance: [
      'Notre famille s’agrandit : venez fêter l’arrivée de notre bébé.',
      'Le septième jour, son nom sera donné : soyez des nôtres.'
    ],
    diplome: [
      'Des années d’efforts, un diplôme en poche : venez le fêter avec nous !',
      'Merci à tous ceux qui nous ont portés jusqu’ici : partageons ce moment.'
    ],
    gala: [
      'Une soirée pour se retrouver, bien manger et danser.',
      'Tenue de soirée de rigueur. Votre présence nous honore.'
    ],
    hommage: [
      'Nous vous invitons à nous rejoindre pour rendre hommage à un être cher.',
      'Il a vécu pour les siens : accompagnons-le une dernière fois.',
      'La famille vous remercie de vos prières et de votre présence.'
    ],
    autre: [
      'Nous serions heureux de vous compter parmi nous.',
      'Merci de confirmer votre présence avant la date limite.',
      'Les enfants sont les bienvenus.',
      'Parking disponible sur place.'
    ]
  };
  S.phrasesFor = function (kind) {
    var k = { anniv: 'anniversaire', concert: 'gala', culture: 'gala', conference: 'gala', inauguration: 'gala' }[kind] || kind;
    return (S.PHRASES[k] || []).concat(S.PHRASES.autre);
  };
})();
