// Marakaj Studio — the renderer (171). One script draws any card document:
// { v: 2, theme: {…}, blocks: [ {id, type, variant, hidden, props, style} ] }.
// The guests' page (/e/<slug>, a card with a document) and the editor
// (/e/<slug>/studio) both use it. Every text is written as text: esc()
// everywhere, never markup from the document. Pictures are the card's own
// (uploads Worker) or the bank's (/cartes/img/<name>.jpg).
(function () {
  'use strict';
  var S = window.Studio = window.Studio || {};

  // ------------------------------------------------------------------ utils
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function txt(s) { return esc(s).replace(/\r?\n/g, '<br>'); }
  function isHex(c) { return typeof c === 'string' && /^#[0-9a-f]{6}$/i.test(c); }
  function rgb(h) { return [parseInt(h.substr(1, 2), 16), parseInt(h.substr(3, 2), 16), parseInt(h.substr(5, 2), 16)]; }
  function hex(c) { return '#' + c.map(function (v) { return ('0' + Math.round(Math.max(0, Math.min(255, v))).toString(16)).slice(-2); }).join(''); }
  function mix(a, b, t) { var x = rgb(a), y = rgb(b); return hex([x[0] + (y[0] - x[0]) * t, x[1] + (y[1] - x[1]) * t, x[2] + (y[2] - x[2]) * t]); }
  function lum(h) { var c = rgb(h).map(function (v) { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }); return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]; }
  function contrast(a, b) { var x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); }
  function uid() { return 'b' + Math.random().toString(36).slice(2, 9); }
  function get(o, path) { return path.split('.').reduce(function (v, k) { return v == null ? v : v[k]; }, o); }
  S.util = { esc: esc, txt: txt, isHex: isHex, mix: mix, lum: lum, contrast: contrast, uid: uid, get: get };

  // ------------------------------------------------------------------ fonts
  // id → [CSS family, Google Fonts query]
  var FONTS = {
    cormorant: ["'Cormorant Garamond', Georgia, serif", 'Cormorant+Garamond:ital,wght@0,400;0,500;0,600;1,400;1,500'],
    playfair: ["'Playfair Display', Georgia, serif", 'Playfair+Display:ital,wght@0,400;0,600;1,400'],
    bodoni: ["'Bodoni Moda', Georgia, serif", 'Bodoni+Moda:ital,wght@0,400;0,600;1,400'],
    cinzel: ["'Cinzel', Georgia, serif", 'Cinzel:wght@400;600'],
    italiana: ["'Italiana', Georgia, serif", 'Italiana'],
    fraunces: ["'Fraunces', Georgia, serif", 'Fraunces:ital,wght@0,400;0,600;1,400'],
    yeseva: ["'Yeseva One', Georgia, serif", 'Yeseva+One'],
    'dm-serif': ["'DM Serif Display', Georgia, serif", 'DM+Serif+Display:ital@0;1'],
    marcellus: ["'Marcellus', Georgia, serif", 'Marcellus'],
    prata: ["'Prata', Georgia, serif", 'Prata'],
    abril: ["'Abril Fatface', Georgia, serif", 'Abril+Fatface'],
    gilda: ["'Gilda Display', Georgia, serif", 'Gilda+Display'],
    tenor: ["'Tenor Sans', Helvetica, sans-serif", 'Tenor+Sans'],
    montserrat: ["'Montserrat', Helvetica, sans-serif", 'Montserrat:wght@300;400;500;600'],
    jost: ["'Jost', Helvetica, sans-serif", 'Jost:wght@300;400;500;600'],
    lora: ["'Lora', Georgia, serif", 'Lora:ital,wght@0,400;0,500;1,400'],
    'eb-garamond': ["'EB Garamond', Georgia, serif", 'EB+Garamond:ital,wght@0,400;0,500;1,400'],
    raleway: ["'Raleway', Helvetica, sans-serif", 'Raleway:wght@300;400;500;600'],
    mulish: ["'Mulish', Helvetica, sans-serif", 'Mulish:wght@300;400;600'],
    nunito: ["'Nunito', Helvetica, sans-serif", 'Nunito:wght@300;400;600'],
    karla: ["'Karla', Helvetica, sans-serif", 'Karla:wght@300;400;600'],
    'work-sans': ["'Work Sans', Helvetica, sans-serif", 'Work+Sans:wght@300;400;500;600'],
    crimson: ["'Crimson Pro', Georgia, serif", 'Crimson+Pro:ital,wght@0,400;0,500;1,400'],
    josefin: ["'Josefin Sans', Helvetica, sans-serif", 'Josefin+Sans:wght@300;400;600'],
    'great-vibes': ["'Great Vibes', cursive", 'Great+Vibes'],
    pinyon: ["'Pinyon Script', cursive", 'Pinyon+Script'],
    parisienne: ["'Parisienne', cursive", 'Parisienne'],
    allura: ["'Allura', cursive", 'Allura'],
    'alex-brush': ["'Alex Brush', cursive", 'Alex+Brush'],
    dancing: ["'Dancing Script', cursive", 'Dancing+Script:wght@400;600'],
    caveat: ["'Caveat', cursive", 'Caveat:wght@400;600'],
    sacramento: ["'Sacramento', cursive", 'Sacramento'],
    tangerine: ["'Tangerine', cursive", 'Tangerine:wght@400;700'],
    syne: ["'Syne', Helvetica, sans-serif", 'Syne:wght@500;700;800'],
    'dm-sans': ["'DM Sans', Helvetica, sans-serif", 'DM+Sans:wght@300;400;500'],
    'source-sans': ["'Source Sans 3', Helvetica, sans-serif", 'Source+Sans+3:wght@300;400;600'],
    archivo: ["'Archivo', Helvetica, sans-serif", 'Archivo:wght@400;600;800'],
    'nunito-sans': ["'Nunito Sans', Helvetica, sans-serif", 'Nunito+Sans:wght@300;400;600'],
    'mrs-saint': ["'Mrs Saint Delafield', cursive", 'Mrs+Saint+Delafield'],
    // the animated designs' own (172)
    anton: ["'Anton', Impact, sans-serif", 'Anton'],
    limelight: ["'Limelight', Georgia, serif", 'Limelight'],
    poiret: ["'Poiret One', Helvetica, sans-serif", 'Poiret+One'],
    homemade: ["'Homemade Apple', cursive", 'Homemade+Apple'],
    julius: ["'Julius Sans One', Helvetica, sans-serif", 'Julius+Sans+One'],
    shippori: ["'Shippori Mincho', Georgia, serif", 'Shippori+Mincho:wght@400;600'],
    'petit-formal': ["'Petit Formal Script', cursive", 'Petit+Formal+Script']
  };
  var FONT_NAMES = {
    cormorant: 'Cormorant', playfair: 'Playfair', bodoni: 'Bodoni', cinzel: 'Cinzel', italiana: 'Italiana', fraunces: 'Fraunces', yeseva: 'Yeseva',
    'dm-serif': 'DM Serif', marcellus: 'Marcellus', prata: 'Prata', abril: 'Abril', gilda: 'Gilda', tenor: 'Tenor', montserrat: 'Montserrat', jost: 'Jost',
    lora: 'Lora', 'eb-garamond': 'Garamond', raleway: 'Raleway', mulish: 'Mulish', nunito: 'Nunito', karla: 'Karla', 'work-sans': 'Work Sans', crimson: 'Crimson',
    josefin: 'Josefin', 'great-vibes': 'Great Vibes', pinyon: 'Pinyon', parisienne: 'Parisienne', allura: 'Allura', 'alex-brush': 'Alex Brush', dancing: 'Dancing',
    caveat: 'Caveat', sacramento: 'Sacramento', tangerine: 'Tangerine', syne: 'Syne', 'dm-sans': 'DM Sans', 'source-sans': 'Source Sans',
    archivo: 'Archivo', 'nunito-sans': 'Nunito Sans', 'mrs-saint': 'Mrs Saint Delafield',
    anton: 'Anton', limelight: 'Limelight', poiret: 'Poiret', homemade: 'Homemade Apple', julius: 'Julius', shippori: 'Shippori', 'petit-formal': 'Petit Formal'
  };
  var PAIRS = [
    { id: 'classique', name: 'Classique', display: 'cormorant', body: 'montserrat', script: 'pinyon' },
    { id: 'romantique', name: 'Romantique', display: 'playfair', body: 'lora', script: 'great-vibes' },
    { id: 'majestueuse', name: 'Majestueuse', display: 'cinzel', body: 'eb-garamond', script: 'parisienne' },
    { id: 'moderne', name: 'Moderne', display: 'bodoni', body: 'jost', script: 'allura' },
    { id: 'epuree', name: 'Épurée', display: 'italiana', body: 'raleway', script: 'sacramento' },
    { id: 'joyeuse', name: 'Joyeuse', display: 'fraunces', body: 'josefin', script: 'caveat' },
    { id: 'wax', name: 'Wax', display: 'yeseva', body: 'mulish', script: 'great-vibes' },
    { id: 'chic', name: 'Chic', display: 'dm-serif', body: 'karla', script: 'alex-brush' },
    { id: 'douce', name: 'Douce', display: 'prata', body: 'nunito', script: 'allura' },
    { id: 'eclat', name: 'Éclat', display: 'abril', body: 'work-sans', script: 'dancing' },
    { id: 'antique', name: 'Antique', display: 'marcellus', body: 'crimson', script: 'tangerine' },
    { id: 'graphique', name: 'Graphique', display: 'tenor', body: 'montserrat', script: 'alex-brush' }
  ];
  S.FONTS = FONTS; S.FONT_NAMES = FONT_NAMES; S.PAIRS = PAIRS;
  function fontOf(id, role) {
    var f = FONTS[id];
    if (f) return f[0];
    return { display: FONTS.cormorant[0], body: FONTS.montserrat[0], script: FONTS['great-vibes'][0] }[role] || FONTS.montserrat[0];
  }
  var loaded = {};
  function loadFonts(ids) {
    var q = ids.filter(function (id) { return FONTS[id] && !loaded[id]; });
    if (!q.length || typeof document === 'undefined') return;
    q.forEach(function (id) { loaded[id] = 1; });
    var l = document.createElement('link'); l.rel = 'stylesheet';
    l.href = 'https://fonts.googleapis.com/css2?' + q.map(function (id) { return 'family=' + FONTS[id][1]; }).join('&') + '&display=swap';
    document.head.appendChild(l);
  }
  S.loadFonts = loadFonts;

  // --------------------------------------------------------------- palettes
  // [id, name, back, paper, ink, accent]: 9 from the classic cards, 24 more.
  var PALETTES = [
    ['ivoire-noir', 'Ivoire et noir', '#141414', '#f6f3ec', '#151515', '#151515'], ['sauge', 'Sauge', '#4e5c47', '#f6f2e8', '#2f3a2c', '#5b6b52'],
    ['terre-cuite', 'Terre cuite', '#7a3b22', '#fbf3ea', '#3b2418', '#b9552f'], ['nuit-or', 'Nuit et or', '#06080f', '#0d1322', '#ece4cf', '#c9a45c'],
    ['rose-poudre', 'Rose poudré', '#b98a84', '#fbf4f1', '#3d2f2d', '#b06a63'], ['bleu-nuit', 'Bleu nuit', '#1d2b45', '#f4f6fa', '#1f2a3d', '#2f4a7a'],
    ['bordeaux', 'Bordeaux', '#4a1520', '#f7f2ea', '#2a1a1c', '#6b1f2a'], ['wax-vert-or', 'Wax vert et or', '#0f4d3a', '#fbf5e8', '#1f2a23', '#c79a2e'],
    ['ivoire-or', 'Ivoire et or', '#3b2f22', '#fbf6ec', '#2b2118', '#b8893b'], ['blanc-sauge', 'Blanc et sauge', '#4f5d4a', '#f7f6f1', '#2e3a2c', '#7a9a6e'],
    ['emeraude-or', 'Émeraude et or', '#0b3d2e', '#f6f1e3', '#13261d', '#c9a24a'], ['bordeaux-creme', 'Bordeaux et crème', '#4b1622', '#f8f1e7', '#2b1418', '#8e2a3b'],
    ['nuit-argent', 'Nuit et argent', '#0f1a2e', '#f2f4f8', '#1a2436', '#8fa3c0'], ['rose', 'Rose', '#c79a96', '#fcf5f3', '#4a3533', '#c0716c'],
    ['terracotta', 'Terracotta', '#8a3f24', '#fbf1e8', '#3a2016', '#c9643a'], ['lavande', 'Lavande', '#5e5277', '#f7f4fa', '#362e46', '#9a86c4'],
    ['moutarde', 'Moutarde et noir', '#1b1a17', '#fbf6e9', '#1b1a17', '#c9951c'], ['turquoise', 'Turquoise et corail', '#0f5257', '#f3faf9', '#163a3d', '#e0664c'],
    ['bogolan', 'Bogolan', '#3d2a1b', '#efe3cf', '#2f2014', '#9a6a3b'], ['faso', 'Faso Dan Fani', '#13315c', '#f8f3e6', '#13284d', '#d9a52c'],
    ['kente', 'Kente', '#1c4a2c', '#fbf3dc', '#1c2a1f', '#c8372a'], ['wax-fuchsia', 'Wax fuchsia', '#5a0f3c', '#fdf2f7', '#3d0b28', '#d2468e'],
    ['indigo', 'Indigo', '#1e2a5a', '#f2f3fb', '#1b2240', '#4f63c9'], ['olive', 'Olive et crème', '#4a4a26', '#f7f4e6', '#2f2f18', '#7d7d32'],
    ['peche', 'Pêche', '#d98f70', '#fff6f1', '#4a2c22', '#d46e4a'], ['menthe', 'Menthe', '#2f6f5a', '#f2faf6', '#1f3a30', '#2f8f68'],
    ['prune-or', 'Prune et or', '#3b1530', '#f8f0f4', '#2a1023', '#b58b45'], ['noir-blanc', 'Noir et blanc', '#111111', '#ffffff', '#111111', '#111111'],
    ['ciel', 'Ciel', '#2b6cb0', '#f3f8fd', '#1c3046', '#2f7fcf'], ['sable-cuivre', 'Sable et cuivre', '#6b4a2b', '#f8efe2', '#3a2a1a', '#a85f26'],
    ['sapin-rouge', 'Sapin et rouge', '#123524', '#f7f3ea', '#13261c', '#a82b25'], ['champagne', 'Champagne', '#8a7558', '#fbf7ef', '#3b3226', '#a88a4f'],
    ['minuit-rose', 'Minuit et rose', '#0e0b16', '#17121f', '#f1e6ee', '#e39ab8']
  ].map(function (p) { return { id: p[0], name: p[1], back: p[2], paper: p[3], ink: p[4], accent: p[5] }; });
  S.PALETTES = PALETTES;
  // The six roles a document's blocks draw with, the missing ones made from the others.
  function colorsOf(theme) {
    var c = (theme && theme.colors) || {}, p = PALETTES[0];
    var paper = isHex(c.paper) ? c.paper : p.paper, ink = isHex(c.ink) ? c.ink : p.ink, accent = isHex(c.accent) ? c.accent : p.accent;
    var back = isHex(c.back) ? c.back : p.back;
    var soft = isHex(c.soft) ? c.soft : mix(paper, accent, 0.1);
    var line = isHex(c.line) ? c.line : mix(paper, ink, 0.2);
    var onAccent = contrast('#ffffff', accent) >= contrast(ink, accent) ? '#ffffff' : ink;
    var onBack = contrast('#ffffff', back) >= contrast('#151515', back) ? '#ffffff' : '#151515';
    return { back: back, paper: paper, ink: ink, accent: accent, soft: soft, line: line, onAccent: onAccent, onBack: onBack };
  }
  S.colorsOf = colorsOf;

  // ----------------------------------------------------------------- motifs
  // Drawn in the accent, as tiles, behind a block or the whole card.
  function svgUrl(s) { return 'url("data:image/svg+xml,' + encodeURIComponent(s) + '")'; }
  var MOTIFS = {
    pois: { name: 'Pois', tile: 28, svg: function (c) { return '<svg xmlns="http://www.w3.org/2000/svg" width="28" height="28"><circle cx="7" cy="7" r="2.2" fill="' + c + '"/><circle cx="21" cy="21" r="2.2" fill="' + c + '"/></svg>'; } },
    losanges: { name: 'Losanges', tile: 36, svg: function (c) { return '<svg xmlns="http://www.w3.org/2000/svg" width="36" height="36"><path d="M18 3 33 18 18 33 3 18Z" fill="none" stroke="' + c + '" stroke-width="1.4"/><path d="M18 12 24 18 18 24 12 18Z" fill="' + c + '"/></svg>'; } },
    wax: { name: 'Wax', tile: 64, svg: function (c) { return '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><g fill="none" stroke="' + c + '" stroke-width="2"><circle cx="32" cy="32" r="14"/><circle cx="32" cy="32" r="7"/><circle cx="0" cy="0" r="14"/><circle cx="64" cy="0" r="14"/><circle cx="0" cy="64" r="14"/><circle cx="64" cy="64" r="14"/></g><circle cx="32" cy="32" r="2.5" fill="' + c + '"/></svg>'; } },
    bogolan: { name: 'Bogolan', tile: 48, svg: function (c) { return '<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48"><g fill="' + c + '"><rect x="4" y="4" width="4" height="16"/><rect x="12" y="4" width="4" height="16"/><rect x="28" y="28" width="16" height="4"/><rect x="28" y="36" width="16" height="4"/><circle cx="36" cy="12" r="3"/><circle cx="12" cy="36" r="3"/></g></svg>'; } },
    kente: { name: 'Kente', tile: 40, svg: function (c) { return '<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40"><g fill="' + c + '"><rect width="20" height="6"/><rect y="14" width="20" height="2"/><rect x="20" y="20" width="20" height="6"/><rect x="20" y="34" width="20" height="2"/><rect x="26" width="2" height="20"/><rect x="6" y="20" width="2" height="20"/></g></svg>'; } },
    vagues: { name: 'Vagues', tile: 40, svg: function (c) { return '<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20"><path d="M0 10 Q10 2 20 10 T40 10" fill="none" stroke="' + c + '" stroke-width="1.5"/></svg>'; } },
    fleurs: { name: 'Fleurs', tile: 56, svg: function (c) { return '<svg xmlns="http://www.w3.org/2000/svg" width="56" height="56"><g fill="' + c + '"><circle cx="14" cy="14" r="3"/><ellipse cx="14" cy="7" rx="2.6" ry="4.4"/><ellipse cx="14" cy="21" rx="2.6" ry="4.4"/><ellipse cx="7" cy="14" rx="4.4" ry="2.6"/><ellipse cx="21" cy="14" rx="4.4" ry="2.6"/><circle cx="42" cy="42" r="2.2"/><circle cx="42" cy="36" r="1.6"/><circle cx="42" cy="48" r="1.6"/><circle cx="36" cy="42" r="1.6"/><circle cx="48" cy="42" r="1.6"/></g></svg>'; } },
    etoiles: { name: 'Étoiles', tile: 60, svg: function (c) { return '<svg xmlns="http://www.w3.org/2000/svg" width="60" height="60"><g fill="' + c + '"><path d="M15 6l2 6 6 2-6 2-2 6-2-6-6-2 6-2z"/><path d="M45 36l1.4 4 4 1.4-4 1.4-1.4 4-1.4-4-4-1.4 4-1.4z"/><circle cx="44" cy="12" r="1.2"/><circle cx="12" cy="44" r="1.2"/></g></svg>'; } },
    lignes: { name: 'Rayures', tile: 16, svg: function (c) { return '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><path d="M0 16 16 0" stroke="' + c + '" stroke-width="1.2"/></svg>'; } }
  };
  S.MOTIFS = MOTIFS;
  function motifCss(id, color) { var m = MOTIFS[id]; return m ? svgUrl(m.svg(color)) : 'none'; }
  S.motifCss = motifCss;

  // ------------------------------------------------------------------ icons
  var IC = {
    pin: '<path d="M12 21s-7-6.6-7-12a7 7 0 0 1 14 0c0 5.4-7 12-7 12z"/><circle cx="12" cy="9" r="2.6"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    dress: '<path d="M9 3l3 3 3-3M10 6l-2 6 3 1-5 8h12l-5-8 3-1-2-6"/>',
    gift: '<rect x="4" y="9" width="16" height="11"/><path d="M4 9h16v3H4zM12 9v11M12 9c-3 0-5-1.5-5-3.5 2 0 5 1.5 5 3.5zM12 9c3 0 5-1.5 5-3.5-2 0-5 1.5-5 3.5z"/>',
    car: '<path d="M4 15l2.5-6h11L20 15v4H4z"/><circle cx="7.5" cy="19" r="1.5"/><circle cx="16.5" cy="19" r="1.5"/>',
    bed: '<path d="M3 19V8M3 15h18v4M21 15v-4H10v4M5 10h3v3H5z"/>',
    phone: '<path d="M6 3h4l2 5-2.5 1.5a11 11 0 0 0 5 5L16 12l5 2v4a2 2 0 0 1-2 2A16 16 0 0 1 4 5a2 2 0 0 1 2-2z"/>',
    info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.5v.5"/>',
    child: '<circle cx="12" cy="6" r="3"/><path d="M8 21v-6l-3-3 2-2 3 2h4l3-2 2 2-3 3v6"/>',
    camera: '<rect x="3" y="7" width="18" height="13" rx="2"/><circle cx="12" cy="13.5" r="3.5"/><path d="M8.5 7l1.5-3h4l1.5 3"/>',
    music: '<path d="M9 18V5l11-2v13"/><circle cx="6.5" cy="18" r="2.5"/><circle cx="17.5" cy="16" r="2.5"/>',
    food: '<path d="M7 3v8M5 3v5a2 2 0 0 0 4 0V3M7 11v10M17 3c-2 2-2 6 0 8v10"/>',
    heart: '<path d="M12 20s-8-4.6-8-10.2A4.3 4.3 0 0 1 12 7a4.3 4.3 0 0 1 8 2.8C20 15.4 12 20 12 20z"/>',
    rings: '<circle cx="9" cy="14" r="5.5"/><circle cx="15" cy="14" r="5.5"/><path d="M13 4l-1 2-1-2 1-1z"/>',
    glass: '<path d="M7 3h10l-1.5 7a3.5 3.5 0 0 1-7 0zM12 14v6M8.5 20h7"/>',
    cake: '<path d="M4 20v-7h16v7zM6 13V9h12v4M12 9V6"/><path d="M12 6c-1-1.5 1-2.5 0-4 1 1.5-1 2.5 0 4z"/>',
    party: '<path d="M5 20l4-11 7 7z"/><path d="M14 6l2-2M17 10l3-1M15 3l.5-2"/>',
    mic: '<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M6 11a6 6 0 0 0 12 0M12 17v4M9 21h6"/>',
    dove: '<path d="M4 13c3 1 6 0 8-3 1 3 4 4 7 3-1 4-4 6-8 6-1.5 0-3-.5-4-1.5L3 19l2-3.5c-1-1-1-2-1-2.5z"/>',
    calendar: '<rect x="4" y="5" width="16" height="15" rx="1"/><path d="M4 10h16M8 3v4M16 3v4"/>',
    star: '<path d="M12 3l2.6 5.6 6 .7-4.5 4 1.3 6-5.4-3.1-5.4 3.1 1.3-6-4.5-4 6-.7z"/>',
    money: '<rect x="3" y="6" width="18" height="12" rx="2"/><circle cx="12" cy="12" r="3"/><path d="M6 9v.01M18 15v.01"/>',
    leaf: '<path d="M5 19c0-8 5-14 14-14 0 9-6 14-14 14zM5 19c3-4 6-7 10-9"/>',
    copy: '<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V5a1 1 0 0 0-1-1H5a1 1 0 0 0-1 1v10a1 1 0 0 0 1 1h3"/>',
    play: '<path d="M8 5v14l11-7z"/>'
  };
  S.ICONS = IC;
  function icon(id) { return '<svg class="st-ic" viewBox="0 0 24 24" aria-hidden="true">' + (IC[id] || IC.info) + '</svg>'; }

  // ------------------------------------------------------------ the event
  var MONTHS = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];
  var DAYS = ['dimanche', 'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi'];
  function hourText(t) { if (!t) return ''; var m = /^(\d{1,2}):(\d{2})/.exec(t); if (!m) return t; return (+m[1]) + ' h' + (m[2] === '00' ? '' : ' ' + m[2]); }
  function facts(ctx) {
    var d = null, p = /^(\d{4})-(\d{2})-(\d{2})$/.exec(ctx.date || '');
    if (p) d = new Date(+p[1], +p[2] - 1, +p[3]);
    var f = { has: !!d, place: ctx.place || '', time: hourText(ctx.time), title: ctx.title || '' };
    if (d) {
      f.day = DAYS[d.getDay()]; f.n = d.getDate(); f.month = MONTHS[d.getMonth()]; f.year = d.getFullYear();
      f.long = f.day + ' ' + (f.n === 1 ? '1er' : f.n) + ' ' + f.month + ' ' + f.year;
      f.short = ('0' + f.n).slice(-2) + ' · ' + ('0' + (d.getMonth() + 1)).slice(-2) + ' · ' + f.year;
      var tm = /^(\d{1,2}):(\d{2})/.exec(ctx.time || '') || [0, 15, 0];
      f.start = new Date(+p[1], +p[2] - 1, +p[3], +tm[1], +tm[2]);
    }
    return f;
  }
  S.facts = facts;

  // --------------------------------------------------------------- pictures
  var STOCK = ['africa-sunset', 'baby-1', 'baby-2', 'baby-3', 'birthday-cake', 'dot-1', 'dot-2', 'family-1', 'gala-1', 'gala-2', 'gala-3', 'garden-1',
    'garden-2', 'garden-3', 'grad-1', 'grad-2', 'grad-3', 'guest-1', 'guest-2', 'guest-3', 'guest-4', 'memorial-1', 'memorial-2', 'party-1', 'party-2',
    'wed-africa-1', 'wed-africa-2', 'wed-bw-1', 'wed-bw-2', 'wed-bw-3', 'wed-couple-1', 'wed-couple-2', 'wed-lake', 'wed-night-1', 'wed-night-2', 'wed-table'];
  S.STOCK = STOCK;
  function picSrc(ph, ctx, w) {
    if (!ph || typeof ph !== 'object') return '';
    if (ph.local) return ph.local;   // the editor's, before the upload answers (never saved)
    if (ph.key && ctx.uploads) return ctx.uploads + '/v1/public/objects/' + encodeURIComponent(ph.key) + (w ? '?w=' + w : '');
    if (ph.stock && STOCK.indexOf(ph.stock) >= 0) return '/cartes/img/' + ph.stock + '.jpg';
    return '';
  }
  S.picSrc = picSrc;
  // An address inside CSS url('…'): the characters that could end it, percent-encoded
  // (the attribute's entities are undone before CSS reads it).
  function cssUrl(u) { return String(u || '').replace(/['"()\\\s]/g, function (c) { return '%' + ('0' + c.charCodeAt(0).toString(16)).slice(-2); }); }
  var FILTERS = { nb: 'grayscale(1)', sepia: 'sepia(.55)', chaud: 'sepia(.22) saturate(1.25) hue-rotate(-6deg)', doux: 'brightness(1.06) contrast(.9) saturate(.85)', vif: 'saturate(1.35) contrast(1.06)' };
  S.FILTERS = FILTERS;
  // A picture in its frame: <figure> with an <img> cropped by its point and zoom.
  function pic(ph, ctx, cls, path, w, ph0) {
    var src = picSrc(ph, ctx, w), pos = ph && Array.isArray(ph.pos) ? ph.pos : [50, 50], z = ph && +ph.zoom > 1 ? Math.min(3, +ph.zoom) : 1;
    var attrs = ' data-p="' + esc(path) + '"';
    if (!src) {
      if (!ctx.editing) return '';
      return '<figure class="st-ph is-empty ' + (cls || '') + '"' + attrs + '><span class="st-ph-add">' + icon('camera') + '<span>' + esc(ph0 || 'Ajouter une photo') + '</span></span></figure>';
    }
    var st = 'object-position:' + (+pos[0] || 0) + '% ' + (+pos[1] || 0) + '%;' + (z > 1 ? 'transform:scale(' + z + ');transform-origin:' + (+pos[0] || 0) + '% ' + (+pos[1] || 0) + '%;' : '') +
      (ph.filter && FILTERS[ph.filter] ? 'filter:' + FILTERS[ph.filter] + ';' : '');
    return '<figure class="st-ph ' + (cls || '') + '"' + attrs + '><img src="' + esc(src) + '" alt="' + esc(ph.alt || '') + '" loading="lazy" decoding="async" style="' + st + '"></figure>';
  }

  // ------------------------------------------------------------ text fields
  // A field of the block, marked for the editor (data-f), styled by the
  // block's style.f[<key>]: s (S M L XL), b, i, u (capitals), c (colour),
  // ff (font), ls (letter spacing), a (alignment: l c r). Empty: gone for the guests, a
  // placeholder in the editor.
  var SIZES = { XS: 0.72, S: 0.85, M: 1, L: 1.25, XL: 1.6, XXL: 2.1 };
  function fkey(path) { return path.replace(/\.\d+\./g, '_').replace(/\./g, '_'); }
  function fieldStyle(b, path) {
    var f = b.style && b.style.f && b.style.f[fkey(path)], s = '';
    if (!f) return '';
    // bigger or smaller than the text's own size (a title stays a title): zoom
    if (f.s && SIZES[f.s] && f.s !== 'M') s += 'zoom:' + SIZES[f.s] + ';';
    if (f.b) s += 'font-weight:700;';
    if (f.i) s += 'font-style:italic;';
    if (f.u) s += 'text-transform:uppercase;';
    if (f.ls) s += 'letter-spacing:' + (f.ls === 2 ? '.24em' : '.1em') + ';';
    if (f.c) s += 'color:' + colorRef(f.c) + ';';
    if (f.a && { l: 1, c: 1, r: 1 }[f.a]) s += 'text-align:' + { l: 'left', c: 'center', r: 'right' }[f.a] + ';';
    if (f.ff) s += 'font-family:' + (f.ff === 'display' || f.ff === 'body' || f.ff === 'script' ? 'var(--st-' + f.ff + ')' : fontOf(f.ff, 'body')) + ';';
    return s;
  }
  function colorRef(c) { return isHex(c) ? c : ({ paper: 'var(--st-paper)', ink: 'var(--st-ink)', accent: 'var(--st-accent)', back: 'var(--st-back)', soft: 'var(--st-soft)', line: 'var(--st-line)', white: '#ffffff', black: '#111111' }[c] || 'inherit'); }
  S.colorRef = colorRef;
  S.fieldStyle = fieldStyle; S.fkey = fkey;
  function F(b, ctx, path, tag, cls, ph, multi) {
    var v = get(b.props || {}, path);
    if ((v == null || v === '') && !ctx.editing) return '';
    var st = fieldStyle(b, path);
    return '<' + tag + ' class="' + cls + '" data-f="' + esc(path) + '"' + (multi ? ' data-multi="1"' : '') + (ph ? ' data-ph="' + esc(ph) + '"' : '') + (st ? ' style="' + st + '"' : '') + '>' + txt(v == null ? '' : v) + '</' + tag + '>';
  }

  // ------------------------------------------------------------------ blocks
  // type → { name, icon, group, desc, variants, make(ctx) → props, draw(b, ctx, f) → inner HTML }
  var B = {};
  S.BLOCKS = B;
  function items(b, key) { var l = b.props && b.props[key]; return Array.isArray(l) ? l : []; }
  // A design's sample (/modele): nothing of a real event. The organiser's
  // look at their own card (« Aperçu », ctx.look) is drawn as the guests'
  // page, and sends nothing either (ctx.demo).
  function sample(ctx) { return !!ctx.demo && !ctx.look; }
  function addBtn(ctx, b, key, label) { return ctx.editing ? '<button type="button" class="st-add-item" data-add="' + esc(key) + '">' + esc(label) + '</button>' : ''; }

  B.cover = {
    name: 'Couverture', icon: 'heart', group: 'Essentiels', desc: 'Les noms, la date, le lieu et une belle photo.',
    variants: [['plein', 'Photo plein écran'], ['cadre', 'Photo encadrée'], ['arche', 'Photo en arche'], ['typo', 'Sans photo']],
    make: function (ctx) { return { kicker: 'Vous êtes invités', names: ctx.title || 'Vos prénoms', sub: '', photo: { stock: 'wed-couple-1', pos: [50, 40] }, showDate: true, showPlace: true }; },
    draw: function (b, ctx, f) { return coverBase(b, ctx, f) + stickers(b, ctx); }
  };
  // the stickers on the cover (173): a few symbols the organiser places, in % of the cover
  var STICKERS = ['💍', '❤️', '💐', '🌸', '🌺', '🌿', '✨', '⭐', '🕊️', '🎉', '🎈', '🎂', '🥂', '🎶', '👑', '🎓', '🙏', '🕯️', '🦋', '☀️'];
  S.STICKERS = STICKERS;
  function stickers(b, ctx) {
    var l = ((b.props || {}).stickers || []).filter(function (x) { return x && STICKERS.indexOf(x.e) >= 0; }).slice(0, 12);
    if (!l.length) return '';
    return '<div class="st-stks" aria-hidden="true">' + l.map(function (x, i) {
      var cx = Math.max(0, Math.min(100, +x.x || 50)), cy = Math.max(0, Math.min(100, +x.y || 50)), sz = Math.max(0.6, Math.min(4, +x.s || 2.6));
      return '<span class="st-stk" data-stk="' + i + '" style="left:' + cx + '%;top:' + cy + '%;font-size:' + sz + 'em;animation-delay:-' + (i * 0.7) + 's">' + x.e + '</span>';
    }).join('') + '</div>';
  }
  function coverBase(b, ctx, f) {
      var p = b.props || {}, v = b.variant || 'plein', date = p.showDate === false ? '' : (p.dateText || (f.has ? f.long + (f.time ? ' · ' + f.time : '') : '')),
        place = p.showPlace === false ? '' : (p.placeText || f.place);
      var words = F(b, ctx, 'kicker', 'p', 'st-kicker', 'Une ligne au-dessus des noms') + F(b, ctx, 'names', 'h1', 'st-names', 'Vos prénoms') +
        F(b, ctx, 'sub', 'p', 'st-sub', 'Une phrase sous les noms') +
        (date ? '<p class="st-date">' + esc(date) + '</p>' : '') + (place ? '<p class="st-place">' + esc(place) + '</p>' : '');
      if (v === 'typo') return '<div class="st-cover-in">' + ornament('fleur') + words + ornament('fleur', true) + '</div>';
      if (v === 'plein') {
        var src = picSrc(p.photo, ctx, 1600);
        if (!src && !ctx.editing) return '<div class="st-cover-in">' + words + '</div>';
        return pic(p.photo, ctx, 'st-cover-ph', 'photo', 1600, 'Ajouter la photo de couverture') + '<div class="st-cover-veil"></div><div class="st-cover-in">' + words + '</div>' + (ctx.editing ? '' : '<span class="st-cue" aria-hidden="true"></span>');
      }
      return pic(p.photo, ctx, v === 'arche' ? 'st-arch' : 'st-framed', 'photo', 1200, 'Ajouter la photo de couverture') + '<div class="st-cover-in">' + words + '</div>';
  }
  B.text = {
    name: 'Texte', icon: 'info', group: 'Essentiels', desc: 'Un titre, un texte, une signature.',
    variants: [['simple', 'Simple'], ['carte', 'Dans une carte'], ['encadre', 'Encadré'], ['lettre', 'Lettre']],
    make: function () { return { kicker: '', title: 'Un mot', body: 'Écrivez ici votre message à vos invités.', sign: '' }; },
    draw: function (b, ctx) {
      var inner = F(b, ctx, 'kicker', 'p', 'st-kicker', 'Petit titre') + F(b, ctx, 'title', 'h2', 'st-h2', 'Titre') + F(b, ctx, 'body', 'p', 'st-body', 'Votre texte', true) + F(b, ctx, 'sign', 'p', 'st-sign', 'Signature');
      return (b.variant === 'carte' || b.variant === 'encadre' || b.variant === 'lettre') ? '<div class="st-box">' + inner + '</div>' : inner;
    }
  };
  B.photo = {
    name: 'Photo', icon: 'camera', group: 'Photos', desc: 'Une photo, cadrée comme vous voulez.',
    variants: [['plein', 'Pleine largeur'], ['cadre', 'Encadrée'], ['cercle', 'Ronde'], ['arche', 'En arche'], ['polaroid', 'Polaroïd']],
    make: function () { return { photo: { stock: 'garden-1', pos: [50, 50] }, caption: '' }; },
    draw: function (b, ctx) {
      var p = b.props || {}, v = b.variant || 'cadre';
      return pic(p.photo, ctx, 'st-shape-' + v, 'photo', v === 'plein' ? 1600 : 1000) + F(b, ctx, 'caption', 'p', 'st-caption', 'Légende');
    }
  };
  B.gallery = {
    name: 'Galerie', icon: 'camera', group: 'Photos', desc: 'Deux à douze photos : grille, mosaïque, carrousel, polaroïds.',
    variants: [['grille', 'Grille'], ['mosaique', 'Mosaïque'], ['carrousel', 'Carrousel'], ['polaroids', 'Polaroïds'], ['arches', 'Arches']],
    make: function () { return { title: 'En images', photos: [{ stock: 'wed-couple-2' }, { stock: 'garden-2' }, { stock: 'wed-table' }, { stock: 'wed-lake' }] }; },
    draw: function (b, ctx) {
      var l = items(b, 'photos');
      return F(b, ctx, 'title', 'h2', 'st-h2', 'Titre') + '<div class="st-gal">' + l.map(function (ph, i) {
        return '<div class="st-gal-it">' + pic(ph, ctx, '', 'photos.' + i, 800) + (ph && ph.caption ? '<span class="st-gal-cap">' + esc(ph.caption) + '</span>' : '') + '</div>';
      }).join('') + '</div>' + addBtn(ctx, b, 'photos', '+ Une photo');
    }
  };
  B.families = {
    name: 'Les familles', icon: 'heart', group: 'Essentiels', desc: 'Les deux familles qui vous invitent.',
    variants: [['cote', 'Côte à côte'], ['pile', 'L\'une sous l\'autre']],
    make: function () { return { title: 'Les familles', left: 'Famille Ouédraogo', leftNote: 'de Tanghin', right: 'Famille Sawadogo', rightNote: 'de Kaya', joiner: '&' }; },
    draw: function (b, ctx) {
      return F(b, ctx, 'title', 'h2', 'st-h2', 'Titre') + '<div class="st-fam"><div>' + F(b, ctx, 'left', 'p', 'st-fam-n', 'Famille') + F(b, ctx, 'leftNote', 'p', 'st-fam-x', 'Précision') + '</div>' +
        F(b, ctx, 'joiner', 'p', 'st-fam-j', '&') + '<div>' + F(b, ctx, 'right', 'p', 'st-fam-n', 'Famille') + F(b, ctx, 'rightNote', 'p', 'st-fam-x', 'Précision') + '</div></div>';
    }
  };
  B.programme = {
    name: 'Programme', icon: 'clock', group: 'Essentiels', desc: 'Les étapes de la journée, avec ou sans horaires.',
    variants: [['timeline', 'Frise'], ['cartes', 'Cartes'], ['liste', 'Liste'], ['menu', 'Menu']],
    make: function () { return { title: 'Le programme', intro: '', showTimes: true, items: [{ time: '15 h', title: 'Cérémonie', detail: 'Sous la tonnelle', icon: 'rings' }, { time: '17 h', title: 'Cocktail', detail: 'Jus frais et bouchées', icon: 'glass' }, { time: '19 h 30', title: 'Dîner', detail: 'Et la première danse', icon: 'food' }] }; },
    draw: function (b, ctx) {
      var p = b.props || {}, l = items(b, 'items'), times = p.showTimes !== false;
      return F(b, ctx, 'title', 'h2', 'st-h2', 'Titre') + F(b, ctx, 'intro', 'p', 'st-lead', 'Une phrase d\'introduction', true) +
        '<ol class="st-prog' + (times ? '' : ' no-times') + '">' + l.map(function (it, i) {
          return '<li data-i="' + i + '">' + (times ? F(b, ctx, 'items.' + i + '.time', 'span', 'st-prog-t', 'Heure') : '') + '<span class="st-prog-dot">' + icon(it && it.icon || 'star') + '</span>' +
            '<div class="st-prog-w">' + F(b, ctx, 'items.' + i + '.title', 'b', 'st-prog-n', 'Étape') + F(b, ctx, 'items.' + i + '.detail', 'span', 'st-prog-d', 'Détail') + '</div></li>';
        }).join('') + '</ol>' + addBtn(ctx, b, 'items', '+ Une étape');
    }
  };
  B.infos = {
    name: 'Bon à savoir', icon: 'info', group: 'Essentiels', desc: 'Tenue, parking, hébergement, enfants…',
    variants: [['liste', 'Liste'], ['grille', 'Grille']],
    make: function () { return { title: 'Bon à savoir', items: [{ icon: 'dress', title: 'Tenue', text: 'Tenue traditionnelle bienvenue.' }, { icon: 'car', title: 'Parking', text: 'Un parking est prévu à l\'entrée.' }] }; },
    draw: function (b, ctx) {
      var l = items(b, 'items');
      return F(b, ctx, 'title', 'h2', 'st-h2', 'Titre') + '<ul class="st-infos">' + l.map(function (it, i) {
        it = it || {};
        return '<li data-i="' + i + '">' + icon(it.icon || 'info') + '<div>' + F(b, ctx, 'items.' + i + '.title', 'b', 'st-info-t', 'Titre') + F(b, ctx, 'items.' + i + '.text', 'span', 'st-info-x', 'Détail', true) +
          (it.href ? '<a class="st-link" href="' + esc(it.href) + '" target="_blank" rel="noopener">' + esc(it.hrefLabel || 'Ouvrir') + '</a>' : '') + '</div></li>';
      }).join('') + '</ul>' + addBtn(ctx, b, 'items', '+ Une info');
    }
  };
  B.countdown = {
    name: 'Compte à rebours', icon: 'clock', group: 'Le jour', desc: 'Les jours, heures et minutes qui restent.',
    variants: [['grand', 'Grands chiffres'], ['pastilles', 'Pastilles']],
    make: function () { return { title: 'Plus que', doneText: 'C\'est aujourd\'hui !' }; },
    draw: function (b, ctx) {
      return F(b, ctx, 'title', 'p', 'st-kicker', 'Titre') + '<div class="st-cd" data-cd>' + ['jours', 'heures', 'min', 'sec'].map(function (u, i) { return '<div><b data-u="' + i + '">0</b><span>' + u + '</span></div>'; }).join('') + '</div>';
    }
  };
  B.place = {
    name: 'Le lieu', icon: 'pin', group: 'Le jour', desc: 'L\'adresse et le bouton « Itinéraire ».',
    variants: [['simple', 'Simple'], ['carte', 'Avec un plan']],
    make: function (ctx) { return { title: 'Le lieu', name: ctx.place || 'Le lieu', address: '', note: '', href: '' }; },
    draw: function (b, ctx) {
      var p = b.props || {}, href = p.href || (p.name || ctx.place ? 'https://www.google.com/maps/search/?api=1&query=' + encodeURIComponent((p.address || p.name || ctx.place || '').trim()) : '');
      return (b.variant === 'carte' ? '<div class="st-map" aria-hidden="true">' + icon('pin') + '</div>' : '') + F(b, ctx, 'title', 'p', 'st-kicker', 'Titre') + F(b, ctx, 'name', 'h2', 'st-h2', 'Nom du lieu') + F(b, ctx, 'address', 'p', 'st-body', 'Adresse', true) +
        F(b, ctx, 'note', 'p', 'st-lead', 'Un mot (parking, repère…)', true) + (href ? '<a class="st-btn" href="' + esc(href) + '" target="_blank" rel="noopener">' + icon('pin') + 'Itinéraire</a>' : '') +
        (ctx.editing && !p.href ? '<p class="st-note">Pour un itinéraire exact : Réglages du bloc, collez le lien Google Maps du lieu.</p>' : '');
    }
  };
  B.calendar = {
    name: 'Ajouter au calendrier', icon: 'calendar', group: 'Le jour', desc: 'Un bouton pour noter la date dans le téléphone.',
    variants: [['bouton', 'Bouton']],
    make: function () { return { title: 'Notez la date', label: 'Ajouter à mon calendrier' }; },
    draw: function (b, ctx, f) {
      return F(b, ctx, 'title', 'p', 'st-kicker', 'Titre') + (f.has ? '<p class="st-h2 st-cal-d">' + esc(f.long) + (f.time ? ' · ' + esc(f.time) : '') + '</p>' : '') +
        '<button type="button" class="st-btn" data-cal>' + icon('calendar') + '<span data-f="label">' + esc((b.props && b.props.label) || 'Ajouter à mon calendrier') + '</span></button>';
    }
  };
  B.contribution = {
    name: 'Contribution', icon: 'money', group: 'Les invités', desc: 'Orange Money, Wave, Moov, banque — avec « Copier ».',
    variants: [['cartes', 'Cartes'], ['liste', 'Liste']],
    make: function () { return { title: 'Contribution', text: 'Pour celles et ceux qui le souhaitent.', lines: [{ label: 'Orange Money', value: '70 00 00 00' }, { label: 'Wave', value: '70 00 00 00' }] }; },
    draw: function (b, ctx) {
      var l = items(b, 'lines');
      return F(b, ctx, 'title', 'h2', 'st-h2', 'Titre') + F(b, ctx, 'text', 'p', 'st-lead', 'Un mot', true) + '<div class="st-contrib">' + l.map(function (it, i) {
        it = it || {};
        return '<div class="st-contrib-it" data-i="' + i + '">' + F(b, ctx, 'lines.' + i + '.label', 'b', 'st-contrib-l', 'Moyen') + F(b, ctx, 'lines.' + i + '.value', 'span', 'st-contrib-v', 'Numéro') +
          (it.value ? '<button type="button" class="st-copy" data-copy="' + esc(it.value) + '">' + icon('copy') + 'Copier</button>' : '') + '</div>';
      }).join('') + '</div>' + addBtn(ctx, b, 'lines', '+ Un moyen');
    }
  };
  B.quote = {
    name: 'Citation', icon: 'star', group: 'Textes', desc: 'Un verset, un proverbe, une citation.',
    variants: [['grande', 'Grande'], ['encadree', 'Encadrée']],
    make: function () { return { text: 'L\'amour est patient, l\'amour est bon.', author: '1 Corinthiens 13, 4' }; },
    draw: function (b, ctx) { return '<blockquote class="st-quote">' + F(b, ctx, 'text', 'p', 'st-quote-t', 'La citation', true) + F(b, ctx, 'author', 'cite', 'st-quote-a', 'Auteur') + '</blockquote>'; }
  };
  // the answers' closing day (173): « YYYY-MM-DD », closed the day after (on the guest's clock; the server holds it too)
  function frDay(d) { var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(d || ''); return m ? +m[3] + ' ' + ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'][+m[2] - 1] + ' ' + m[1] : ''; }
  function rsvpClosed(p) { if (!p || !/^\d{4}-\d{2}-\d{2}$/.test(p.closes || '')) return false; var n = new Date(), t = n.getFullYear() + '-' + ('0' + (n.getMonth() + 1)).slice(-2) + '-' + ('0' + n.getDate()).slice(-2); return t > p.closes; }
  S.frDay = frDay; S.rsvpClosed = rsvpClosed;
  B.rsvp = {
    name: 'Réponse des invités', icon: 'heart', group: 'Les invités', desc: 'Le formulaire « Je viens / Je ne peux pas ».',
    variants: [['carte', 'Dans une carte'], ['simple', 'Simple']],
    make: function () { return { title: 'Serez-vous des nôtres ?', lead: 'Merci de répondre avant le 1er du mois.', yes: 'Je viens', no: 'Je ne peux pas', askPhone: true, pass: false }; },
    draw: function (b, ctx) {
      var p = b.props || {}, form;
      if (ctx.tickets && !sample(ctx)) form = '<p class="st-lead">Cet événement se fait sur billet. Réservez vos places, payez l\'organisateur, recevez vos billets avec leur QR code.</p><a class="st-btn" href="/e/' + encodeURIComponent(ctx.slug || '') + '/billets' + (ctx.preview ? '?apercu=' + encodeURIComponent(ctx.preview) : '') + '">Réserver mes billets</a>';
      else if (ctx.rsvp_on === false && !ctx.editing) form = '<p class="st-lead st-closed">Les réponses sont fermées pour cet événement.</p>';
      else if (rsvpClosed(p) && !ctx.editing) form = '<p class="st-lead st-closed">Les réponses sont closes depuis le ' + esc(frDay(p.closes)) + '. Merci !</p>';
      else form = '<form class="st-rsvp" novalidate><label>Votre nom<input name="name" autocomplete="name" maxlength="80"></label><label>Nombre de personnes<select name="n">' +
        [1, 2, 3, 4, 5, 6].map(function (n) { return '<option>' + n + '</option>'; }).join('') + '</select></label>' +
        (p.askPhone !== false && !sample(ctx) ? '<label>WhatsApp, si vous voulez un rappel la veille<input name="wa" inputmode="tel" autocomplete="tel" placeholder="+226 70 00 00 00" maxlength="24"></label>' : '') +
        '<div class="st-choice"><button type="button" data-a="oui">' + esc(p.yes || 'Je viens') + '</button><button type="button" data-a="non">' + esc(p.no || 'Je ne peux pas') + '</button></div>' +
        (p.questions || []).slice(0, 3).map(function (q, i) { return q && q.q ? '<label>' + esc(q.q) + '<input name="q' + i + '" maxlength="300"></label>' : ''; }).join('') +
        (p.closes && /^\d{4}-\d{2}-\d{2}$/.test(p.closes) ? '<p class="st-lead st-by">Merci de répondre avant le ' + esc(frDay(p.closes)) + '.</p>' : '') +
        '<label>Un mot (facultatif)<textarea name="msg" rows="2" maxlength="500"></textarea></label><button type="submit" class="st-btn">Envoyer ma réponse</button><p class="st-done" role="status"></p><div class="st-pass" hidden></div></form>';
      return '<div class="st-box">' + F(b, ctx, 'title', 'h2', 'st-h2', 'Titre') + F(b, ctx, 'lead', 'p', 'st-lead', 'Un mot', true) + form + '</div>';
    }
  };
  B.tickets = {
    name: 'Billets', icon: 'star', group: 'Les invités', desc: 'Le bouton « Réserver mes billets » (billetterie ouverte).',
    variants: [['bouton', 'Bouton']],
    make: function () { return { title: 'Billets', text: 'Réservez vos places en quelques secondes.', label: 'Réserver mes billets' }; },
    draw: function (b, ctx) {
      if (!ctx.tickets && !ctx.editing) return '';
      return F(b, ctx, 'title', 'h2', 'st-h2', 'Titre') + F(b, ctx, 'text', 'p', 'st-lead', 'Un mot', true) +
        '<a class="st-btn" href="/e/' + encodeURIComponent(ctx.slug || '') + '/billets' + (ctx.preview ? '?apercu=' + encodeURIComponent(ctx.preview) : '') + '">' + esc((b.props && b.props.label) || 'Réserver mes billets') + '</a>' +
        (ctx.editing && !ctx.tickets ? '<p class="st-note">La billetterie n\'est pas ouverte pour cette carte : vos invités ne verront pas ce bloc.</p>' : '');
    }
  };
  B.album = {
    name: 'Album des invités', icon: 'camera', group: 'Les invités', desc: 'Les invités ajoutent leurs photos de la fête.',
    variants: [['grille', 'Grille']],
    make: function () { return { title: 'Vos photos', lead: 'Ajoutez les photos que vous prenez : elles rejoignent l\'album de l\'événement, sous votre prénom.' }; },
    draw: function (b, ctx) {
      var closed = ctx.album_on === false || !ctx.uploads || sample(ctx);
      return F(b, ctx, 'title', 'h2', 'st-h2', 'Titre') + F(b, ctx, 'lead', 'p', 'st-lead', 'Un mot', true) +
        (closed ? (ctx.editing ? '<p class="st-note">L\'album est fermé : vos invités verront « L\'album est fermé pour cet événement ».</p>' : '<p class="st-lead st-closed">L\'album est fermé pour cet événement.</p>')
          : '<div class="st-album" data-album><label>Votre nom (sous la photo)<input name="who" maxlength="60" placeholder="Nora"></label><label class="st-btn">' + icon('camera') + 'Ajouter des photos<input type="file" accept="image/*" multiple hidden></label><p class="st-done" role="status"></p><div class="st-album-g"></div></div>');
    }
  };
  B.pass = {
    name: 'Carte d\'invité (QR)', icon: 'star', group: 'Les invités', desc: 'Le QR de l\'invité qui a répondu, scanné à l\'entrée.',
    variants: [['carte', 'Carte']],
    make: function () { return { title: 'Votre carte d\'invité', text: 'Présentez ce QR code à l\'entrée.' }; },
    draw: function (b, ctx) {
      return F(b, ctx, 'title', 'h2', 'st-h2', 'Titre') + F(b, ctx, 'text', 'p', 'st-lead', 'Un mot', true) + '<div class="st-pass" data-passbox>' + (ctx.editing ? '<p class="st-note">Le QR apparaît ici pour l\'invité qui a répondu « Je viens » sur son téléphone.</p>' : '') + '</div>';
    }
  };
  B.video = {
    name: 'Vidéo', icon: 'play', group: 'Photos', desc: 'Une vidéo YouTube.',
    variants: [['large', 'Large']],
    make: function () { return { title: '', url: '' }; },
    draw: function (b, ctx) {
      var p = b.props || {}, id = ytId(p.url);
      return F(b, ctx, 'title', 'h2', 'st-h2', 'Titre') + (id ? '<div class="st-video" data-yt="' + esc(id) + '"><img src="https://i.ytimg.com/vi/' + esc(id) + '/hqdefault.jpg" alt="" loading="lazy"><button type="button" aria-label="Lire la vidéo">' + icon('play') + '</button></div>'
        : (ctx.editing ? '<p class="st-note">Collez le lien YouTube dans les réglages du bloc.</p>' : ''));
    }
  };
  function ytId(u) { var m = /(?:youtube\.com\/(?:watch\?v=|embed\/|shorts\/)|youtu\.be\/)([A-Za-z0-9_-]{11})/.exec(String(u || '')); return m ? m[1] : ''; }
  S.ytId = ytId;
  // the music library (173): twelve pieces free of rights (CC0), served by the site
  var TRACKS = [['village-heureux', 'Village heureux', 'Joyeuse, rythmes d’Afrique de l’Ouest'], ['ouest-afrique', 'À l’ouest de l’Afrique', 'Douce, guitare et percussions'],
    ['soleil-rasta', 'Soleil rasta', 'Reggae ensoleillé'], ['kalimba', 'Kalimba', 'Calme, pour un baptême ou un hommage'], ['sagesse-soleil', 'Sagesse au soleil', 'Paisible'],
    ['ukulele', 'Ukulélé', 'Légère et souriante'], ['ukulele-siffle', 'Ukulélé sifflé', 'Joyeuse, pour un anniversaire'], ['tranche-de-vie', 'Tranche de vie', 'Tendre'],
    ['cafe-doux', 'Café doux', 'Feutrée, pour une soirée'], ['quelque-part', 'Quelque part', 'Rêveuse, pour un mariage'], ['cafe-matin', 'Café du matin', 'Détendue'],
    ['rue-soleil', 'Rue au soleil', 'Entraînante']].map(function (x) { return { id: x[0], name: x[1], mood: x[2] }; });
  S.TRACKS = TRACKS;
  function trackSrc(p) {
    if (p && /^https:\/\//.test(p.url || '')) return p.url;   // the organiser's own link first
    if (p && p.track && TRACKS.some(function (x) { return x.id === p.track; })) return '/cartes/musique/' + p.track + '.mp3';
    return '';
  }
  S.trackSrc = trackSrc;
  B.music = {
    name: 'Musique', icon: 'music', group: 'Photos', desc: 'Une musique que l\'invité lance d\'un toucher.',
    variants: [['bouton', 'Bouton']],
    make: function () { return { title: 'Notre chanson', track: 'quelque-part' }; },
    draw: function (b, ctx) {
      var u = trackSrc(b.props || {});
      return F(b, ctx, 'title', 'p', 'st-kicker', 'Titre') + (u ? '<button type="button" class="st-btn" data-music="' + esc(u) + '">' + icon('play') + '<span>Écouter</span></button>' : (ctx.editing ? '<p class="st-note">Choisissez une musique dans les réglages du bloc.</p>' : ''));
    }
  };
  function ornament(kind, flip) {
    var o = {
      fleur: '<svg viewBox="0 0 240 24" aria-hidden="true"><path d="M0 12h96M144 12h96" stroke="currentColor" stroke-width="1"/><path d="M120 4c4 4 4 12 0 16-4-4-4-12 0-16zM108 12c4-4 12-4 16 0-4 4-12 4-16 0zM132 12c-4-4-12-4-16 0 4 4 12 4 16 0z" fill="currentColor" opacity=".85"/></svg>',
      ligne: '<svg viewBox="0 0 240 12" aria-hidden="true"><path d="M20 6h200" stroke="currentColor" stroke-width="1"/><circle cx="120" cy="6" r="3" fill="currentColor"/></svg>',
      vague: '<svg viewBox="0 0 240 16" aria-hidden="true"><path d="M0 8q10-8 20 0t20 0 20 0 20 0 20 0 20 0 20 0 20 0 20 0 20 0 20 0 20 0" fill="none" stroke="currentColor" stroke-width="1.4"/></svg>',
      points: '<svg viewBox="0 0 240 12" aria-hidden="true"><g fill="currentColor"><circle cx="96" cy="6" r="2"/><circle cx="108" cy="6" r="2.5"/><circle cx="120" cy="6" r="3.5"/><circle cx="132" cy="6" r="2.5"/><circle cx="144" cy="6" r="2"/></g></svg>',
      coeur: '<svg viewBox="0 0 240 20" aria-hidden="true"><path d="M30 10h70M140 10h70" stroke="currentColor"/><path d="M120 17s-9-5-9-10a4.5 4.5 0 0 1 9-1.5 4.5 4.5 0 0 1 9 1.5c0 5-9 10-9 10z" fill="currentColor"/></svg>',
      wax: '<svg viewBox="0 0 240 24" aria-hidden="true"><g fill="none" stroke="currentColor" stroke-width="1.4"><circle cx="120" cy="12" r="9"/><circle cx="120" cy="12" r="4"/><circle cx="96" cy="12" r="5"/><circle cx="144" cy="12" r="5"/><path d="M10 12h76M154 12h76"/></g></svg>'
    };
    return '<div class="st-orn' + (flip ? ' flip' : '') + '">' + (o[kind] || o.ligne) + '</div>';
  }
  S.ornament = ornament;
  B.divider = {
    name: 'Ornement', icon: 'leaf', group: 'Mise en page', desc: 'Une séparation élégante entre deux blocs.',
    variants: [['fleur', 'Fleur'], ['ligne', 'Ligne'], ['vague', 'Vague'], ['points', 'Points'], ['coeur', 'Cœur'], ['wax', 'Wax']],
    make: function () { return {}; },
    draw: function (b) { return ornament(b.variant || 'fleur'); }
  };
  B.spacer = {
    name: 'Espace', icon: 'leaf', group: 'Mise en page', desc: 'De l\'air entre deux blocs.',
    variants: [['s', 'Petit'], ['m', 'Moyen'], ['l', 'Grand']],
    make: function () { return {}; },
    draw: function () { return ''; }
  };
  B.footer = {
    name: 'Pied de page', icon: 'heart', group: 'Mise en page', desc: 'Les noms, la date et un dernier mot.',
    variants: [['simple', 'Simple']],
    make: function (ctx) { return { text: ctx.title || '' }; },
    draw: function (b, ctx, f) {
      // « Partager la carte » (173): the guest passes it on, the organiser sees it counted
      return F(b, ctx, 'text', 'p', 'st-foot-t', 'Un dernier mot') + (f.has ? '<p class="st-foot-d">' + esc(f.short) + '</p>' : '') +
        (b.props && b.props.share === false ? '' : '<button type="button" class="st-btn st-btn-ghost" data-share>Partager la carte</button>') +
        '<p class="st-brand">Carte créée avec Marakaj</p>';
    }
  };
  B.free = {
    name: 'Bloc libre', icon: 'star', group: 'Textes', desc: 'Un texte, une photo et un bouton, comme vous voulez.',
    variants: [['photo-haut', 'Photo en haut'], ['photo-cote', 'Photo à côté'], ['texte', 'Sans photo']],
    make: function () { return { title: 'Un titre', body: 'Votre texte.', photo: { stock: 'party-1' }, button: '', href: '' }; },
    draw: function (b, ctx) {
      var p = b.props || {}, v = b.variant || 'photo-haut';
      var words = '<div class="st-free-w">' + F(b, ctx, 'title', 'h2', 'st-h2', 'Titre') + F(b, ctx, 'body', 'p', 'st-body', 'Texte', true) +
        (p.href && p.button ? '<a class="st-btn" href="' + esc(p.href) + '" target="_blank" rel="noopener">' + esc(p.button) + '</a>' : (ctx.editing && p.button ? '<span class="st-btn">' + esc(p.button) + '</span>' : '')) + '</div>';
      return v === 'texte' ? words : '<div class="st-free">' + pic(p.photo, ctx, 'st-free-ph', 'photo', 1000) + words + '</div>';
    }
  };
  B.button = {
    name: 'Bouton', icon: 'star', group: 'Textes', desc: 'Un lien : liste de cadeaux, page, numéro…',
    variants: [['plein', 'Plein'], ['contour', 'Contour']],
    make: function () { return { label: 'Voir la liste de cadeaux', href: '' }; },
    draw: function (b, ctx) {
      var p = b.props || {};
      if (!p.href && !ctx.editing) return '';
      return '<a class="st-btn' + (b.variant === 'contour' ? ' ghost' : '') + '"' + (p.href ? ' href="' + esc(p.href) + '" target="_blank" rel="noopener"' : '') + '><span data-f="label">' + esc(p.label || 'Bouton') + '</span></a>' + (ctx.editing && !p.href ? '<p class="st-note">Ajoutez le lien dans les réglages du bloc.</p>' : '');
    }
  };
  B.faq = {
    name: 'Questions', icon: 'info', group: 'Textes', desc: 'Les questions que vos invités se posent.',
    variants: [['liste', 'Liste']],
    make: function () { return { title: 'Vos questions', items: [{ q: 'Les enfants sont-ils invités ?', a: 'Oui, avec plaisir !' }, { q: 'Où se garer ?', a: 'Un parking est prévu à l\'entrée.' }] }; },
    draw: function (b, ctx) {
      var l = items(b, 'items');
      return F(b, ctx, 'title', 'h2', 'st-h2', 'Titre') + '<div class="st-faq">' + l.map(function (it, i) {
        return '<details data-i="' + i + '"' + (ctx.editing ? ' open' : '') + '><summary>' + F(b, ctx, 'items.' + i + '.q', 'span', 'st-faq-q', 'La question') + '</summary>' + F(b, ctx, 'items.' + i + '.a', 'p', 'st-faq-a', 'La réponse', true) + '</details>';
      }).join('') + '</div>' + addBtn(ctx, b, 'items', '+ Une question');
    }
  };
  B.menu = {
    name: 'Menu du repas', icon: 'food', group: 'Le jour', desc: 'Entrées, plats, desserts, boissons.',
    variants: [['carte', 'Carte de menu']],
    make: function () { return { title: 'Le menu', items: [{ title: 'Entrées', text: 'Salade composée · Brochettes' }, { title: 'Plats', text: 'Riz gras · Poulet braisé · Tô' }, { title: 'Desserts', text: 'Gâteau des mariés' }] }; },
    draw: function (b, ctx) {
      var l = items(b, 'items');
      return '<div class="st-box st-menu">' + F(b, ctx, 'title', 'h2', 'st-h2', 'Titre') + ornament('ligne') + l.map(function (it, i) {
        return '<div class="st-menu-it" data-i="' + i + '">' + F(b, ctx, 'items.' + i + '.title', 'b', 'st-menu-t', 'Service') + F(b, ctx, 'items.' + i + '.text', 'p', 'st-menu-x', 'Les plats', true) + '</div>';
      }).join('') + addBtn(ctx, b, 'items', '+ Un service') + '</div>';
    }
  };
  B.story = {
    name: 'Notre histoire', icon: 'heart', group: 'Textes', desc: 'Les grandes dates de votre histoire.',
    variants: [['frise', 'Frise']],
    make: function () { return { title: 'Notre histoire', items: [{ date: '2019', title: 'La rencontre', text: 'Un soir de festival à Bobo.' }, { date: '2024', title: 'La demande', text: 'Sous le baobab de la cour familiale.' }] }; },
    draw: function (b, ctx) {
      var l = items(b, 'items');
      return F(b, ctx, 'title', 'h2', 'st-h2', 'Titre') + '<ol class="st-story">' + l.map(function (it, i) {
        it = it || {};
        return '<li data-i="' + i + '">' + F(b, ctx, 'items.' + i + '.date', 'span', 'st-story-d', 'Date') + '<div>' + F(b, ctx, 'items.' + i + '.title', 'b', 'st-story-t', 'Titre') + F(b, ctx, 'items.' + i + '.text', 'p', 'st-story-x', 'Le récit', true) +
          (it.photo ? pic(it.photo, ctx, 'st-story-ph', 'items.' + i + '.photo', 700) : '') + '</div></li>';
      }).join('') + '</ol>' + addBtn(ctx, b, 'items', '+ Une date');
    }
  };
  B.dresscode = {
    name: 'Tenue', icon: 'dress', group: 'Le jour', desc: 'Le code vestimentaire et ses couleurs.',
    variants: [['pastilles', 'Pastilles']],
    make: function () { return { title: 'La tenue', text: 'Pagne de la famille : wax vert et or.', colors: ['#0f6b4f', '#c9a24a', '#fbf5e8'] }; },
    draw: function (b, ctx) {
      var c = items(b, 'colors').filter(isHex);
      return F(b, ctx, 'title', 'h2', 'st-h2', 'Titre') + F(b, ctx, 'text', 'p', 'st-body', 'Le code vestimentaire', true) + (c.length ? '<div class="st-swatches">' + c.map(function (x) { return '<span style="background:' + x + '"></span>'; }).join('') + '</div>' : '');
    }
  };

  // ------------------------------------------------------------ the scenes
  // The animated cards' living pictures (172), drawn behind a block by
  // /evenements/scenes.js, loaded only when a card has one. « tone » says
  // whether the picture is light or dark: the veil and the words follow it.
  // The « lx- » ones are painted by the phone's graphics chip: Marakaj Pro.
  var SCENES = [
    ['silk', 'Soie', 'light'], ['garden', 'Jardin fleuri', 'light'], ['orchard', 'Verger en fleurs', 'light'], ['sky', 'Ciel du soir', 'light'],
    ['savanna', 'Savane sous la lune', 'light'], ['loom', 'Métier à tisser', 'dark'], ['weave', 'Bandes tissées', 'dark'], ['blobs', 'Formes douces', 'light'],
    ['velvet', 'Velours', 'dark'], ['party', 'Confettis', 'light'], ['sahel', 'Sahel', 'dark'], ['ocean', 'Océan', 'dark'], ['lotus', 'Étang aux lotus', 'dark'],
    ['forest', 'Forêt', 'dark'], ['sakura', 'Cerisiers', 'light'], ['sunflowers', 'Tournesols', 'light'], ['lanterns', 'Lanternes', 'dark'],
    ['roses', 'Roseraie', 'light'], ['desert', 'Désert', 'dark'], ['champagne', 'Champagne', 'light'], ['butterflies', 'Papillons', 'light'],
    ['globe', 'Village sous la neige', 'light'], ['snowfall', 'Neige', 'light'], ['fireworks', 'Feux d’artifice', 'dark'], ['aurora', 'Aurore boréale', 'dark'],
    ['lx-savane', 'Savane d’or', 'dark'], ['lx-lotus', 'Étang de lotus', 'dark'], ['lx-foret', 'Forêt enchantée', 'dark'], ['lx-cerisiers', 'Paravent de cerisiers', 'light'],
    ['lx-tournesols', 'Champ d’or', 'dark'], ['lx-lanternes', 'Nuit des lanternes', 'dark'], ['lx-roseraie', 'Velours & roses', 'dark'], ['lx-dunes', 'Caravane des dunes', 'dark'],
    ['lx-rivage', 'Carte du rivage', 'dark'], ['lx-champagne', 'Champagne Gatsby', 'dark'], ['lx-herbier', 'Herbier aux papillons', 'light'], ['lx-givre', 'Fenêtre givrée', 'dark'],
    ['lx-feux', 'Grand soir', 'dark'], ['lx-aurore', 'Boréale', 'dark']
  ].map(function (x) { return { id: x[0], name: x[1], tone: x[2], premium: x[0].indexOf('lx-') === 0 }; });
  var SCENE = {}; SCENES.forEach(function (x) { SCENE[x.id] = x; });
  S.SCENES = SCENES; S.SCENE = SCENE;
  // the veil over a scene: its colour (the scene's tone unless chosen) and its strength
  function sceneVeil(s) {
    var sc = SCENE[s.scene], tone = s.veil === 'light' || s.veil === 'dark' ? s.veil : (sc ? sc.tone : 'dark');
    return { tone: tone, dim: s.dim != null ? Math.max(0, Math.min(0.85, +s.dim)) : (tone === 'light' ? 0.45 : 0.3) };
  }
  S.sceneVeil = sceneVeil;

  // ------------------------------------------------------------------ render
  var PAD = { S: 'st-pad-s', M: '', L: 'st-pad-l' };
  function blockStyle(b) {
    var s = b.style || {}, cls = [], css = '';
    var bg = s.bg || (b.type === 'cover' && (b.variant || 'plein') === 'plein' ? 'none' : 'paper');
    if (bg === 'scene' && s.scene && SCENE[s.scene]) cls.push('st-bg-scene', 'st-scene-' + sceneVeil(s).tone);
    else if (bg === 'photo' && s.bgPhoto) cls.push('st-bg-photo');
    else if (isHex(bg)) { css += '--bg:' + bg + ';--ink-b:' + (contrast('#ffffff', bg) >= contrast('#151515', bg) ? '#ffffff' : '#151515') + ';'; cls.push('st-bg-hex'); }
    else cls.push('st-bg-' + ({ paper: 'paper', soft: 'soft', accent: 'accent', back: 'back', none: 'none', ink: 'ink' }[bg] || 'paper'));
    if (s.align) cls.push('st-al-' + ({ left: 'l', center: 'c', right: 'r' }[s.align] || 'c'));
    if (s.pad && PAD[s.pad] != null) cls.push(PAD[s.pad]);
    if (s.size && SIZES[s.size]) css += '--fs:' + SIZES[s.size] + 'em;';
    if (s.ink) css += 'color:' + colorRef(s.ink) + ';';
    if (s.motif) cls.push('st-motif');
    if (s.sep && s.sep !== 'none') cls.push('st-sep');
    return { cls: cls.join(' '), css: css };
  }
  S.renderBlock = function (b, ctx, f) {
    var def = B[b.type]; if (!def) return '';
    f = f || facts(ctx);
    var inner;
    try { inner = def.draw(b, ctx, f); } catch (e) { inner = ctx.editing ? '<p class="st-note">Ce bloc ne peut pas être affiché.</p>' : ''; }
    if (!inner && !ctx.editing && b.type !== 'spacer') return '';
    var st = blockStyle(b), s = b.style || {};
    var bgPh = s.bg === 'photo' && s.bgPhoto ? '<div class="st-bgph" style="background-image:url(\'' + esc(cssUrl(picSrc(s.bgPhoto, ctx, 1600))) + '\');' + (Array.isArray(s.bgPhoto.pos) ? 'background-position:' + s.bgPhoto.pos[0] + '% ' + s.bgPhoto.pos[1] + '%;' : '') + '"></div><div class="st-bgveil" style="opacity:' + (s.dim != null ? Math.max(0, Math.min(0.85, +s.dim)) : 0.45) + '"></div>' : '';
    if (s.bg === 'scene' && s.scene && SCENE[s.scene]) {
      var vl = sceneVeil(s);
      bgPh = '<div class="st-scene" data-scene="' + esc(s.scene) + '" aria-hidden="true"></div><div class="st-bgveil st-veil-' + vl.tone + '" style="opacity:' + vl.dim + '"></div>';
    }
    return '<section class="st-b st-t-' + esc(b.type) + ' v-' + esc(b.variant || (def.variants[0] && def.variants[0][0]) || 'base') + ' ' + st.cls + (b.hidden ? ' is-hidden' : '') + '" data-bid="' + esc(b.id) + '" data-type="' + esc(b.type) + '"' + (st.css ? ' style="' + st.css + '"' : '') + '>' +
      bgPh + (s.sep && s.sep !== 'none' ? ornament(s.sep) : '') + '<div class="st-in">' + inner + '</div></section>';
  };
  S.render = function (doc, ctx) {
    var f = facts(ctx), blocks = (doc && Array.isArray(doc.blocks)) ? doc.blocks : [];
    return blocks.filter(function (b) { return b && B[b.type] && (ctx.editing || !b.hidden); }).map(function (b) { return S.renderBlock(b, ctx, f); }).join('');
  };
  // The theme on the card's root: the six colours, the three fonts, the corners, the motif, the motion.
  S.applyTheme = function (root, theme) {
    theme = theme || {};
    var c = colorsOf(theme), fo = theme.fonts || {}, st = root.style;
    ['back', 'paper', 'ink', 'accent', 'soft', 'line', 'onAccent', 'onBack'].forEach(function (k) { st.setProperty('--st-' + k.replace(/[A-Z]/g, function (m) { return '-' + m.toLowerCase(); }), c[k]); });
    // the accent as text, where it reads (else the background's own text colour)
    var on = function (bg, alt) { return contrast(c.accent, bg) >= 2.6 ? c.accent : alt; };
    st.setProperty('--st-a-paper', on(c.paper, c.ink)); st.setProperty('--st-a-soft', on(c.soft, c.ink));
    st.setProperty('--st-a-back', on(c.back, c.onBack)); st.setProperty('--st-a-ink', on(c.ink, c.paper));
    st.setProperty('--st-display', fontOf(fo.display, 'display'));
    st.setProperty('--st-body', fontOf(fo.body, 'body'));
    st.setProperty('--st-script', fontOf(fo.script, 'script'));
    loadFonts([fo.display || 'cormorant', fo.body || 'montserrat', fo.script || 'great-vibes']);
    var m = theme.motif && MOTIFS[theme.motif.id] ? theme.motif : null;
    st.setProperty('--st-motif', m ? motifCss(m.id, c.accent) : 'none');
    st.setProperty('--st-motif-size', m ? (MOTIFS[m.id].tile * (m.scale ? Math.max(0.5, Math.min(2.5, +m.scale)) : 1)) + 'px' : '0px');
    st.setProperty('--st-motif-o', m ? String(m.opacity != null ? Math.max(0.03, Math.min(0.6, +m.opacity)) : 0.12) : '0');
    root.classList.remove('st-r-droit', 'st-r-doux', 'st-r-rond', 'st-m-aucune', 'st-m-douce', 'st-m-vivante', 'st-motif-all');
    root.classList.add('st-r-' + ({ droit: 'droit', doux: 'doux', rond: 'rond' }[theme.corners] || 'doux'));
    root.classList.add('st-m-' + ({ aucune: 'aucune', douce: 'douce', vivante: 'vivante' }[theme.motion] || 'douce'));
    if (m && m.all) root.classList.add('st-motif-all');
  };

  // ------------------------------------------------------------- behaviour
  function api(ctx, fn, body) {
    var a = ctx.api || {};
    if (!a.url || !a.key) return Promise.reject(new Error('Pas de serveur.'));
    return fetch(a.url.replace(/\/+$/, '') + '/rest/v1/rpc/' + fn, { method: 'POST', headers: { 'Content-Type': 'application/json', apikey: a.key, Authorization: 'Bearer ' + a.key }, body: JSON.stringify(body) })
      .then(function (r) { return r.json().then(function (j) { if (!r.ok) throw new Error((j && (j.message || j.hint)) || 'Refusé.'); return j; }, function () { if (!r.ok) throw new Error('Refusé.'); return null; }); });
  }
  S.api = api;
  function toast(root, msg) {
    var t = document.querySelector('.st-toast');
    if (!t) { t = document.createElement('div'); t.className = 'st-toast'; t.setAttribute('role', 'status'); document.body.appendChild(t); }
    t.textContent = msg; t.classList.add('on'); clearTimeout(toast.t);
    toast.t = setTimeout(function () { t.classList.remove('on'); }, Math.max(2600, String(msg).length * 60));   // time to read it
  }
  S.toast = toast;
  function passKey(ctx) { return 'mk-pass-' + (ctx.slug || ''); }
  function drawPass(box, ctx, id, name) {
    if (!box || !id) return;
    box.hidden = false;
    box.innerHTML = '<div class="st-pass-qr" role="img" aria-label="QR code de votre carte d\'invité"></div><div><b></b><small>Carte d\'invité · à présenter à l\'entrée</small></div>';
    box.querySelector('b').textContent = name || 'Invité';
    var draw = function () {
      try { var q = qrcode(0, 'M'); q.addData(location.origin + '/e/' + encodeURIComponent(ctx.slug) + '/invite/' + id); q.make(); box.querySelector('.st-pass-qr').innerHTML = q.createSvgTag({ cellSize: 3, margin: 0, scalable: true }); }
      catch (e) { box.querySelector('.st-pass-qr').textContent = 'QR'; }
    };
    if (window.qrcode) { draw(); return; }
    var s = document.createElement('script'); s.src = 'https://cdnjs.cloudflare.com/ajax/libs/qrcode-generator/1.4.4/qrcode.min.js'; s.onload = draw; document.head.appendChild(s);
  }
  function shrink(file, max, done) {
    var url = URL.createObjectURL(file), im = new Image();
    im.onload = function () {
      var k = Math.min(1, max / Math.max(im.width, im.height)), c = document.createElement('canvas');
      c.width = Math.round(im.width * k); c.height = Math.round(im.height * k); c.getContext('2d').drawImage(im, 0, 0, c.width, c.height);
      URL.revokeObjectURL(url); c.toBlob(function (b) { done(b, c); }, 'image/jpeg', 0.84);
    };
    im.onerror = function () { URL.revokeObjectURL(url); done(null); }; im.src = url;
  }
  S.shrink = shrink;
  function ics(ctx, f) {
    if (!f.start) return null;
    var p = function (n) { return ('0' + n).slice(-2); }, d = f.start, e = new Date(d.getTime() + 4 * 3600e3);
    var fmt = function (x) { return x.getFullYear() + p(x.getMonth() + 1) + p(x.getDate()) + 'T' + p(x.getHours()) + p(x.getMinutes()) + '00'; };
    return ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Marakaj//Carte//FR', 'BEGIN:VEVENT', 'UID:' + (ctx.slug || 'carte') + '@marakaj.com', 'DTSTAMP:' + fmt(new Date()),
      'DTSTART:' + fmt(d), 'DTEND:' + fmt(e), 'SUMMARY:' + (ctx.title || 'Invitation').replace(/[,;]/g, ' '), 'LOCATION:' + (ctx.place || '').replace(/[,;]/g, ' '),
      'URL:' + location.origin + '/e/' + (ctx.slug || ''), 'END:VEVENT', 'END:VCALENDAR'].join('\r\n');
  }
  // Countdowns, copy buttons, the calendar, the answer form, the album, videos, music.
  S.wire = function (root, ctx, doc) {
    var f = facts(ctx);
    clearInterval(root._cd);
    var cds = root.querySelectorAll('[data-cd]');
    if (cds.length && f.start) {
      var tick = function () {
        var ms = f.start - Date.now(), v = [Math.floor(ms / 864e5), Math.floor(ms / 36e5) % 24, Math.floor(ms / 6e4) % 60, Math.floor(ms / 1e3) % 60];
        Array.prototype.forEach.call(cds, function (cd) {
          if (ms <= 0) { var blk = cd.closest('[data-bid]'), b = doc && doc.blocks.filter(function (x) { return x.id === (blk && blk.getAttribute('data-bid')); })[0]; cd.innerHTML = '<p class="st-h2">' + esc((b && b.props && b.props.doneText) || 'C\'est aujourd\'hui !') + '</p>'; return; }
          Array.prototype.forEach.call(cd.querySelectorAll('[data-u]'), function (x) { var i = +x.getAttribute('data-u'); x.textContent = i ? ('0' + v[i]).slice(-2) : v[i]; });
        });
      };
      tick(); root._cd = setInterval(tick, 1000);
    }
    if (ctx.editing) return;
    root.addEventListener('click', function (e) {
      var c = e.target.closest('[data-copy]');
      if (c) { var t = c.getAttribute('data-copy'), p = navigator.clipboard && navigator.clipboard.writeText ? navigator.clipboard.writeText(t) : Promise.reject(); p.then(function () { toast(root, 'Copié : ' + t); }, function () { toast(root, t); }); return; }
      var cal = e.target.closest('[data-cal]');
      if (cal) { var s = ics(ctx, f); if (!s) return; var a = document.createElement('a'); a.href = 'data:text/calendar;charset=utf-8,' + encodeURIComponent(s); a.download = (ctx.slug || 'invitation') + '.ics'; document.body.appendChild(a); a.click(); a.remove(); return; }
      var yt = e.target.closest('[data-yt]');
      if (yt && !yt.querySelector('iframe')) { yt.innerHTML = '<iframe src="https://www.youtube-nocookie.com/embed/' + encodeURIComponent(yt.getAttribute('data-yt')) + '?autoplay=1&rel=0" title="Vidéo" allow="autoplay; encrypted-media; picture-in-picture" allowfullscreen></iframe>'; return; }
      var sh = e.target.closest('[data-share]');
      if (sh && !ctx.editing) {
        var link = location.origin + '/e/' + encodeURIComponent(ctx.slug || '');
        var said = (doc.meta && doc.meta.title) || ctx.title || 'Notre invitation';
        var beacon = function () { if (ctx.slug && !ctx.demo) try { navigator.sendBeacon('/e/' + encodeURIComponent(ctx.slug) + '/partage'); } catch (x) {} };
        if (navigator.share) navigator.share({ title: said, text: said, url: link }).then(beacon, function () {});
        else { beacon(); location.href = 'https://wa.me/?text=' + encodeURIComponent(said + ' ' + link); }
      }
      var mu = e.target.closest('[data-music]');
      if (mu) { var au = mu._a || (mu._a = new Audio(mu.getAttribute('data-music'))); if (au.paused) { au.play(); mu.querySelector('span').textContent = 'Pause'; } else { au.pause(); mu.querySelector('span').textContent = 'Écouter'; } }
    });
    // the answer (event_rsvp, 152): the pass (158) when « Je viens » and the card asks for it
    var saved = null; try { saved = JSON.parse(localStorage.getItem(passKey(ctx)) || 'null'); } catch (e) { saved = null; }
    var wantsPass = (doc.blocks || []).some(function (b) { return !b.hidden && ((b.type === 'rsvp' && b.props && b.props.pass) || b.type === 'pass'); });
    Array.prototype.forEach.call(root.querySelectorAll('.st-rsvp'), function (form) {
      var ans = null, out = form.querySelector('.st-done'), box = form.querySelector('.st-pass'), rb = form.closest('[data-bid]'), blk = (doc.blocks || []).filter(function (x) { return rb && x.id === rb.getAttribute('data-bid'); })[0] || {};
      Array.prototype.forEach.call(form.querySelectorAll('[data-a]'), function (btn) {
        btn.addEventListener('click', function () { ans = btn.getAttribute('data-a'); Array.prototype.forEach.call(form.querySelectorAll('[data-a]'), function (x) { x.setAttribute('aria-pressed', String(x === btn)); }); });
      });
      if (saved && saved.pass && blk.props && blk.props.pass) drawPass(box, ctx, saved.pass, saved.name);
      form.addEventListener('submit', function (e) {
        e.preventDefault();
        var name = form.elements.name.value.trim();
        if (!name) { out.textContent = 'Écrivez votre nom, pour que nous sachions qui répond.'; return; }
        if (!ans) { out.textContent = 'Dites-nous si vous venez : « ' + ((blk.props && blk.props.yes) || 'Je viens') + ' » ou « ' + ((blk.props && blk.props.no) || 'Je ne peux pas') + ' ».'; return; }
        var thanks = ans === 'oui' ? 'Merci ' + name + ' ! Votre présence est notée.' : 'Merci ' + name + ', nous penserons à vous.';
        if (ctx.demo || !ctx.slug) { out.textContent = thanks; return; }
        var sub = form.querySelector('[type=submit]'); sub.disabled = true; out.textContent = 'Envoi…';
        var wa = form.elements.wa && form.elements.wa.value.trim();
        // the answers to the organiser's questions (173), in their order
        var extra = wa ? { whatsapp: wa } : {}, qs = ((blk.props && blk.props.questions) || []).slice(0, 3);
        if (qs.length) extra.answers = qs.map(function (q, i) { var f = form.elements['q' + i]; return f ? f.value.trim().slice(0, 300) : ''; });
        api(ctx, 'event_rsvp', { p_slug: ctx.slug, p_preview: ctx.preview || null, p_name: name, p_people: parseInt(form.elements.n.value, 10) || 1, p_answer: ans, p_message: form.elements.msg.value.trim() || null, p_extra: extra })
          .then(function (id) {
            out.textContent = thanks;
            if (typeof id === 'string' && ans === 'oui') {
              try { localStorage.setItem(passKey(ctx), JSON.stringify({ pass: id, name: name })); } catch (e2) {}
              if (blk.props && blk.props.pass) drawPass(box, ctx, id, name);
              Array.prototype.forEach.call(root.querySelectorAll('[data-passbox]'), function (pb) { drawPass(pb, ctx, id, name); });
            }
          }, function (err) { sub.disabled = false; out.textContent = err && err.message ? err.message : 'La réponse n\'est pas passée. Réessayez.'; });
      });
    });
    if (wantsPass && saved && saved.pass) Array.prototype.forEach.call(root.querySelectorAll('[data-passbox]'), function (pb) { drawPass(pb, ctx, saved.pass, saved.name); });
    // the guests' album (155/164)
    Array.prototype.forEach.call(root.querySelectorAll('[data-album]'), function (box) {
      var grid = box.querySelector('.st-album-g'), say = box.querySelector('.st-done'), input = box.querySelector('input[type=file]'), who = box.querySelector('input[name=who]'), rules = {};
      var fig = function (src, name) { var d = document.createElement('figure'); d.innerHTML = '<img alt="" loading="lazy"><figcaption></figcaption>'; d.querySelector('img').src = src; d.querySelector('figcaption').textContent = name || 'Un invité'; return d; };
      api(ctx, 'event_album_rules', { p_slug: ctx.slug, p_preview: ctx.preview || null }).then(function (j) { rules = j || {}; }, function () {});
      api(ctx, 'event_album', { p_slug: ctx.slug, p_preview: ctx.preview || null }).then(function (l) { (Array.isArray(l) ? l : []).forEach(function (p) { if (p && p.key) grid.appendChild(fig(picSrc({ key: p.key }, ctx, 400), p.guest)); }); }, function () {});
      input.addEventListener('change', function () {
        var files = Array.prototype.slice.call(input.files); input.value = '';
        if (!files.length) return;
        if (ctx.demo) { say.textContent = 'Aperçu : vos invités ajoutent leurs photos sur la vraie carte.'; return; }
        say.textContent = files.length > 1 ? 'Envoi des photos…' : 'Envoi de la photo…';
        var pass = (function () { try { var s = JSON.parse(localStorage.getItem(passKey(ctx)) || 'null'); return s && s.pass || ''; } catch (e) { return ''; } })();
        Promise.all(files.map(function (file) {
          return new Promise(function (res) {
            shrink(file, 1400, function (blob) {
              if (!blob) return res(null);
              fetch(ctx.uploads + '/v1/events/' + encodeURIComponent(ctx.slug) + '/album?apercu=' + encodeURIComponent(ctx.preview || '') + '&invite=' + encodeURIComponent(who.value.trim()) + '&pass=' + encodeURIComponent(pass), { method: 'POST', headers: { 'Content-Type': 'image/jpeg' }, body: blob })
                .then(function (r) { return r.json().then(function (j) { if (!r.ok || !j || !j.key) throw new Error(j && j.error ? j.error : 'La photo n\'est pas passée.'); return j; }); })
                .then(function (j) { if (!rules.review) grid.insertBefore(fig(URL.createObjectURL(blob), who.value.trim()), grid.firstChild); res(j); }, function (err) { say.textContent = err.message; res(null); });
            });
          });
        })).then(function (r) { var k = r.filter(Boolean).length; if (k) say.textContent = rules.review ? (k > 1 ? k + ' photos envoyées : visibles après validation' : 'Photo envoyée : visible après validation') : (k > 1 ? k + ' photos ajoutées à l\'album' : 'Photo ajoutée à l\'album'); });
      });
    });
  };
  // Blocks appear as they come into view (motion « douce » and « vivante »).
  S.motion = function (root) {
    if (!('IntersectionObserver' in window) || root.classList.contains('st-m-aucune') || window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      Array.prototype.forEach.call(root.querySelectorAll('.st-b'), function (b) { b.classList.add('in'); }); return;
    }
    var io = new IntersectionObserver(function (es) { es.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); } }); }, { rootMargin: '0px 0px -8% 0px' });
    Array.prototype.forEach.call(root.querySelectorAll('.st-b'), function (b) { io.observe(b); });
  };
  // The scenes behind the blocks (172): /evenements/scenes.js, loaded once,
  // the first time a card has one. A redraw (the editor redraws on every
  // change) keeps a scene that is still there — the same block, the same
  // picture, the same colours: its canvases move into the new block, and
  // the graphics chip is not asked to start again.
  var live = [], sceneJs = null;
  function loadScenes() {
    if (window.MaraScenes) return Promise.resolve(window.MaraScenes);
    if (!sceneJs) sceneJs = new Promise(function (ok, ko) {
      var t = document.createElement('script'); t.src = '/evenements/scenes.js'; t.async = true;
      t.onload = function () { if (window.MaraScenes) ok(window.MaraScenes); else ko(new Error('scenes')); };
      t.onerror = function () { sceneJs = null; ko(new Error('scenes')); };
      document.head.appendChild(t);
    });
    return sceneJs;
  }
  S.scenes = function (root, theme) {
    var els = Array.prototype.slice.call(root.querySelectorAll('.st-scene[data-scene]'));
    var c = colorsOf(theme || {}), pal = { bg: c.paper, ink: c.ink, accent: c.accent, soft: c.soft, deep: c.back };
    var pk = [pal.bg, pal.ink, pal.accent, pal.soft, pal.deep].join(''), keep = [];
    var want = els.map(function (el) {
      var bl = el.closest('[data-bid]');
      return { el: el, key: (bl ? bl.getAttribute('data-bid') : '') + '|' + el.getAttribute('data-scene') + '|' + pk };
    });
    want.forEach(function (w) {
      var old = live.filter(function (x) { return x.key === w.key && keep.indexOf(x) < 0; })[0];
      if (old && old.ctl) { old.ctl.canvases.forEach(function (cv) { w.el.appendChild(cv); }); old.el = w.el; keep.push(old); w.done = true; }
    });
    live.filter(function (x) { return keep.indexOf(x) < 0; }).forEach(function (x) { if (x.ctl) x.ctl.stop(); });
    live = keep;
    var todo = want.filter(function (w) { return !w.done; });
    if (!todo.length) return Promise.resolve();
    return loadScenes().then(function (M) {
      todo.forEach(function (w) {
        if (!w.el.isConnected) return;
        var ctl = M.mount(w.el, w.el.getAttribute('data-scene'), pal);
        if (ctl) live.push({ key: w.key, el: w.el, ctl: ctl });
      });
    }, function () { /* no scene: the block keeps its colours */ });
  };
  // Everything at once: the guests' page.
  S.mount = function (root, doc, ctx) {
    root.classList.add('st-root');
    S.applyTheme(root, doc.theme);
    root.innerHTML = '<main class="st-card">' + S.render(doc, ctx) + '</main>';
    S.wire(root, ctx, doc);
    S.scenes(root, doc.theme);
    if (!ctx.editing) S.motion(root);
  };
})();
