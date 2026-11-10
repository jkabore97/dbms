// Marakaj — the living scenes (172). Every animated card's pictures are
// drawn by code, live: a silk that ripples, a garden that grows, a sky
// that turns to night, a pagne woven thread by thread, and the fourteen
// Premium scenes the phone's graphics chip paints (sun, water, dunes,
// mist, frost) under a hand-drawn foreground (petals, koï, lanterns,
// fireworks). Taken whole from the animated page (/evenements/), where
// they were born, so that Studio can put any of them behind a block:
//
//   MaraScenes.mount(element, id, palette) -> { stop() }
//
// « element » is filled (its canvases sized to it); « id » is a 2D scene
// (« garden ») or a Premium one (« lx-savane »); « palette » is the card's
// colours as #rrggbb: { bg, ink, accent, soft, deep }. A scene draws only
// while it is on the screen; with « less motion » asked, it is drawn once.
(function () {
  'use strict';
  if (window.MaraScenes) return;
  var RM = !!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);

  // ================= generated scenes =================
  // Every picture here is drawn by code, live: it keeps moving on its own (wind, light, weaving)
  // and the scroll pushes it further. A scene only draws while it is on screen.
  var TAU = Math.PI * 2;
  function clamp(x, a, b) { return Math.max(a == null ? 0 : a, Math.min(b == null ? 1 : b, x)); }
  function ease(x) { x = clamp(x); return 1 - Math.pow(1 - x, 3); }
  function sstep(a, b, x) { x = clamp((x - a) / (b - a)); return x * x * (3 - 2 * x); }
  function rng(seed) { return function () { seed = (seed * 16807) % 2147483647; return (seed - 1) / 2147483646; }; }
  function hex(c) {
    c = (c || '').trim();
    if (c.charAt(0) === '#') { if (c.length === 4) c = '#' + c[1] + c[1] + c[2] + c[2] + c[3] + c[3]; return [parseInt(c.substr(1, 2), 16), parseInt(c.substr(3, 2), 16), parseInt(c.substr(5, 2), 16)]; }
    var m = c.match(/\d+(\.\d+)?/g); return m ? m.slice(0, 3).map(Number) : [0, 0, 0];
  }
  function mix(a, b, t) { return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]; }
  function rgb(a, al) { return 'rgba(' + (a[0] | 0) + ',' + (a[1] | 0) + ',' + (a[2] | 0) + ',' + (al == null ? 1 : al) + ')'; }

  // (the page's own runner is replaced by MaraScenes.mount below)

  // ---- shared drawings ----
  function flower(g, x, y, R, open, cOut, cIn, rot, nP, layers, curl) {
    g.save(); g.translate(x, y); g.rotate(rot);
    for (var L = 0; L < layers; L++) {
      var k = 1 - L / (layers + .4), r = R * k * (.3 + .7 * open), n = nP + L, off = L * .55 + curl;
      var gr = g.createLinearGradient(0, 0, 0, -r); gr.addColorStop(0, cIn); gr.addColorStop(1, cOut);
      g.fillStyle = gr; g.strokeStyle = 'rgba(255,255,255,.22)'; g.lineWidth = .8;
      for (var i = 0; i < n; i++) {
        g.save(); g.rotate(i / n * TAU + off); g.scale(1, .85 + .15 * open);
        g.beginPath(); g.moveTo(0, 0); g.bezierCurveTo(r * .62, -r * .22, r * .52, -r * 1.02, 0, -r); g.bezierCurveTo(-r * .52, -r * 1.02, -r * .62, -r * .22, 0, 0);
        g.fill(); g.stroke(); g.restore();
      }
    }
    g.fillStyle = cIn; g.beginPath(); g.arc(0, 0, R * .16, 0, TAU); g.fill();
    g.fillStyle = 'rgba(255,230,150,.9)';
    for (var j = 0; j < 9; j++) { var a = j / 9 * TAU; g.beginPath(); g.arc(Math.cos(a) * R * .1, Math.sin(a) * R * .1, R * .03 + .6, 0, TAU); g.fill(); }
    g.restore();
  }
  function makeTree(R, depth, spread) {
    function b(d) {
      var n = {d: d, ph: R() * TAU, k: [], a: 0, l: 1};
      if (d > 0) { var c = d > depth - 2 ? 2 : (R() < .55 ? 2 : 3); for (var i = 0; i < c; i++) { var ch = b(d - 1); ch.a = (i - (c - 1) / 2) * (spread + R() * .25) + (R() - .5) * .25; ch.l = .66 + R() * .14; n.k.push(ch); } }
      return n;
    }
    return b(depth);
  }
  function drawTree(g, T, x, y, len, t, wind, bark, leaves, blossom) {
    (function rec(n, x, y, ang, len, w) {
      var depthFromTop = n.d, sway = (Math.sin(t * 1.3 + n.ph) * .018 + wind * .02) * (7 - Math.min(7, depthFromTop));
      var a = ang + n.a + sway, x2 = x + Math.sin(a) * len, y2 = y - Math.cos(a) * len;
      g.strokeStyle = bark; g.lineWidth = Math.max(.8, w); g.lineCap = 'round';
      g.beginPath(); g.moveTo(x, y); g.quadraticCurveTo((x + x2) / 2 + Math.cos(a) * len * .08, (y + y2) / 2, x2, y2); g.stroke();
      if (n.d <= 1) {
        for (var i = 0; i < 3; i++) {
          var ox = Math.sin(n.ph * 3 + i * 1.7) * len * .9, oy = Math.cos(n.ph * 5 + i) * len * .7, flick = Math.sin(t * 2.2 + n.ph + i) * 1.2;
          g.fillStyle = leaves[(i + (n.ph * 10 | 0)) % leaves.length];
          g.beginPath(); g.ellipse(x2 + ox + flick, y2 + oy, len * .55, len * .4, n.ph + i, 0, TAU); g.fill();
        }
        if (blossom) { g.fillStyle = blossom; for (var j = 0; j < 3; j++) { g.beginPath(); g.arc(x2 + Math.sin(n.ph * 7 + j * 2) * len * .7, y2 + Math.cos(n.ph * 4 + j) * len * .6, len * .16, 0, TAU); g.fill(); } }
      }
      n.k.forEach(function (c) { rec(c, x2, y2, a, len * c.l, w * .68); });
    })(T, x, y, 0, len, len * .14);
  }
  function grassField(R, w, h, n, base, tall) { var a = []; for (var i = 0; i < n; i++) a.push({x: R() * w, h: h * (base + tall * R()), ph: R() * TAU, wd: .8 + R() * 1.8, c: R()}); return a; }
  function drawGrass(g, bl, h, t, colA, colB, wind) {
    [[colA, true], [colB, false]].forEach(function (cc) {
      g.strokeStyle = cc[0]; g.lineWidth = 1.5; g.beginPath();
      bl.forEach(function (b) {
        if ((b.c > .5) !== cc[1]) return;
        var sway = Math.sin(t * 1.6 + b.ph + b.x * .01) * b.h * .12 + wind * b.h * .18;
        g.moveTo(b.x, h); g.quadraticCurveTo(b.x + sway * .3, h - b.h * .55, b.x + sway, h - b.h);
      });
      g.stroke();
    });
  }
  var moonCache = null;
  function moonImage() {
    if (moonCache) return moonCache;
    var S = 512, c = document.createElement('canvas'); c.width = c.height = S; var g = c.getContext('2d'), R = rng(42);
    g.save(); g.beginPath(); g.arc(S / 2, S / 2, S / 2 - 2, 0, TAU); g.clip();
    var base = g.createRadialGradient(S * .4, S * .36, S * .05, S / 2, S / 2, S / 2);
    base.addColorStop(0, '#fffaf0'); base.addColorStop(.55, '#ece0c2'); base.addColorStop(1, '#bfb08b');
    g.fillStyle = base; g.fillRect(0, 0, S, S);
    // the « seas »: wide soft dark patches
    [[.36, .38, .16], [.58, .3, .11], [.62, .55, .14], [.42, .62, .09], [.3, .55, .07]].forEach(function (m) {
      var r = g.createRadialGradient(S * m[0], S * m[1], 0, S * m[0], S * m[1], S * m[2]); r.addColorStop(0, 'rgba(120,110,90,.42)'); r.addColorStop(1, 'rgba(120,110,90,0)'); g.fillStyle = r; g.fillRect(0, 0, S, S);
    });
    for (var i = 0; i < 70; i++) {
      var x = R() * S, y = R() * S, r = 3 + Math.pow(R(), 2.2) * 34;
      var cr = g.createRadialGradient(x - r * .2, y - r * .2, r * .1, x, y, r); cr.addColorStop(0, 'rgba(90,80,60,.35)'); cr.addColorStop(.75, 'rgba(90,80,60,.12)'); cr.addColorStop(.86, 'rgba(255,250,235,.35)'); cr.addColorStop(1, 'rgba(255,250,235,0)');
      g.fillStyle = cr; g.beginPath(); g.arc(x, y, r, 0, TAU); g.fill();
    }
    for (var k = 0; k < 5000; k++) { g.fillStyle = R() > .5 ? 'rgba(255,255,255,.05)' : 'rgba(60,50,30,.06)'; g.fillRect(R() * S, R() * S, 1.5, 1.5); }
    var sh = g.createRadialGradient(S * .35, S * .3, S * .2, S * .55, S * .6, S * .7); sh.addColorStop(0, 'rgba(0,0,0,0)'); sh.addColorStop(1, 'rgba(30,25,20,.35)'); g.fillStyle = sh; g.fillRect(0, 0, S, S);
    g.restore(); moonCache = c; return c;
  }

  var SCN = {};
  // La Lettre: silk that ripples, gold dust that floats
  SCN.silk = function (s, P) {
    var ow = 110, oh = Math.max(40, Math.round(ow * s.h / s.w)), oc = document.createElement('canvas'); oc.width = ow; oc.height = oh;
    var og = oc.getContext('2d'), img = og.createImageData(ow, oh), R = rng(3), dust = [];
    var A = mix(P.soft, P.deep, .18), B = mix(P.bg, P.white, .5), Cg = mix(P.accent, P.white, .55);
    for (var i = 0; i < 46; i++) dust.push({x: R(), y: R(), r: .6 + R() * 1.8, v: .004 + R() * .01, ph: R() * TAU});
    return function (g, w, h, t, p) {
      var d = img.data, k = 0, tt = t * .32 + p * 3;
      for (var y = 0; y < oh; y++) for (var x = 0; x < ow; x++) {
        var v = Math.sin(x * .085 + tt + Math.sin(y * .045 + tt * .6) * 2.4) * .55 + Math.sin((x + y) * .035 - tt * .8) * .3 + Math.sin(y * .12 + tt * .4) * .15;
        var sh = (v + 1) / 2, c = sh > .82 ? mix(B, Cg, (sh - .82) * 3) : mix(A, B, sh / .82);
        d[k++] = c[0]; d[k++] = c[1]; d[k++] = c[2]; d[k++] = 255;
      }
      og.putImageData(img, 0, 0); g.imageSmoothingEnabled = true; g.drawImage(oc, 0, 0, w, h);
      dust.forEach(function (q) { var y = ((q.y - t * q.v - p * .4) % 1 + 1) % 1, x = q.x + Math.sin(t * .6 + q.ph) * .02; g.globalAlpha = .35 + .65 * Math.abs(Math.sin(t * 1.4 + q.ph)); g.fillStyle = rgb(Cg); g.beginPath(); g.arc(x * w, y * h, q.r, 0, TAU); g.fill(); });
      g.globalAlpha = 1;
    };
  };
  // Le Jardin: a garden in the wind
  function gardenScene(s, P, opt) {
    var W = s.w, H = s.h, R = rng(opt.seed);
    var cols = [[P.accent, mix(P.accent, P.white, .65)], [mix(P.accent, P.white, .35), P.white], [mix(P.accent, P.deep, .35), mix(P.accent, P.white, .4)], [mix(P.soft, P.white, .1), mix(P.accent, P.white, .5)]];
    var fl = [], n = opt.flowers;
    for (var i = 0; i < n; i++) { var dp = R(), c = cols[(R() * 4) | 0]; fl.push({x: (i + .2 + R() * .6) / n * W, h: H * (opt.fh[0] + opt.fh[1] * R()) * (.7 + dp * .5), r: (22 + 26 * R()) * (.6 + dp * .7), d: dp, ph: R() * TAU, out: rgb(c[0]), inn: rgb(c[1]), np: 5 + ((R() * 3) | 0), L: 3 + ((R() * 2) | 0), rot: R() * TAU, del: R() * 1.4}); }
    fl.sort(function (a, b) { return a.d - b.d; });
    var grassB = grassField(R, W, H, Math.round(W / 4), .05, .08), grassF = grassField(R, W, H, Math.round(W / 5), .03, .06);
    var tree = makeTree(R, 6, .46), pet = [], bf = [{ph: 0}, {ph: 2.6}, {ph: 4.1}];
    for (var j = 0; j < 16; j++) pet.push({x: R(), y: R(), v: .02 + R() * .04, ph: R() * TAU, s: 3 + R() * 4});
    var leafCols = [rgb(mix(P.accent, P.green, .55), .75), rgb(mix(P.soft, P.green, .45), .7), rgb(mix(P.accent, P.deep, .3), .6)];
    var stem = rgb(mix(P.green, P.deep, .3)), bark = rgb(mix(P.deep, P.soft, .25)), bl = rgb(mix(P.accent, P.white, .55), .9);
    return function (g, w, h, t, p) {
      var open = ease((t - .2) / 2.8) * (.75 + .25 * clamp(p * 2)), wind = Math.sin(t * .45) * .6 + Math.sin(t * .17 + 1) * .4;
      var sky = g.createLinearGradient(0, 0, 0, h); sky.addColorStop(0, rgb(P.bg)); sky.addColorStop(1, rgb(mix(P.soft, P.bg, .25))); g.fillStyle = sky; g.fillRect(0, 0, w, h);
      var sun = g.createRadialGradient(w * .22, h * .18, 0, w * .22, h * .18, w * .7); sun.addColorStop(0, rgb(P.white, .7)); sun.addColorStop(1, rgb(P.white, 0)); g.fillStyle = sun; g.fillRect(0, 0, w, h);
      [[.74, .16, .7, 12], [.82, .26, .85, 18]].forEach(function (hl, k) { g.fillStyle = rgb(mix(P.soft, P.accent, hl[1]), hl[2]); g.beginPath(); g.moveTo(0, h); for (var x = 0; x <= w; x += 8) g.lineTo(x, h * hl[0] - Math.sin(x * .006 + k * 2 + p * .8) * hl[3] - Math.sin(x * .017 + k) * hl[3] * .5); g.lineTo(w, h); g.fill(); });
      drawTree(g, tree, w * opt.treeX, h * .9, h * opt.treeL, t, wind, bark, leafCols, opt.blossom ? bl : null);
      drawGrass(g, grassB, h, t, rgb(mix(P.green, P.soft, .35), .7), rgb(mix(P.accent, P.green, .5), .6), wind);
      fl.forEach(function (f) {
        var o = ease((t - .3 - f.del) / 2.4) * (.7 + .3 * clamp(p * 2.2)), sway = Math.sin(t * .95 + f.ph) * f.h * .06 + wind * f.h * .05;
        var hx = f.x + sway, hy = h - f.h;
        g.strokeStyle = stem; g.lineWidth = 1.4 + f.d * 1.4; g.beginPath(); g.moveTo(f.x, h); g.quadraticCurveTo(f.x + sway * .2, h - f.h * .5, hx, hy); g.stroke();
        g.fillStyle = rgb(mix(P.green, P.soft, .2), .85);
        [.35, .6].forEach(function (u, i) { var lx = f.x + sway * u * u, ly = h - f.h * u; g.save(); g.translate(lx, ly); g.rotate((i ? -1 : 1) * .9 + sway * .01); g.beginPath(); g.ellipse(i ? -9 : 9, 0, 11 + f.d * 5, 4 + f.d * 2, 0, 0, TAU); g.fill(); g.restore(); });
        flower(g, hx, hy, f.r, o, f.out, f.inn, f.rot + Math.sin(t * .5 + f.ph) * .08, f.np, f.L, t * .02);
      });
      drawGrass(g, grassF, h, t, rgb(mix(P.green, P.deep, .25), .8), rgb(mix(P.green, P.accent, .3), .7), wind);
      bf.forEach(function (b, i) {
        var x = w * (.5 + .42 * Math.sin(t * .19 + b.ph)), y = h * (.38 + .16 * Math.sin(t * .31 + b.ph * 2)) - p * h * .1, fl2 = .25 + .75 * Math.abs(Math.sin(t * 9 + b.ph));
        g.save(); g.translate(x, y); g.rotate(Math.sin(t * .7 + b.ph) * .3); g.fillStyle = rgb(i % 2 ? P.accent : mix(P.accent, P.deep, .4), .85);
        [-1, 1].forEach(function (sd) { g.save(); g.scale(sd * fl2, 1); g.beginPath(); g.ellipse(6, -4, 7, 5, .5, 0, TAU); g.ellipse(5, 4, 5, 3.5, -.4, 0, TAU); g.fill(); g.restore(); });
        g.fillStyle = rgb(P.deep); g.fillRect(-.8, -6, 1.6, 12); g.restore();
      });
      pet.forEach(function (q) { var y = ((q.y + t * q.v + p * .3) % 1), x = q.x + Math.sin(t * .8 + q.ph) * .03; g.save(); g.translate(x * w, y * h); g.rotate(t + q.ph); g.fillStyle = rgb(mix(P.accent, P.white, .45), .75); g.beginPath(); g.ellipse(0, 0, q.s, q.s * .55, 0, 0, TAU); g.fill(); g.restore(); });
    };
  }
  SCN.garden = function (s, P) { return gardenScene(s, P, {seed: 11, flowers: Math.max(7, Math.round(s.w / 52)), fh: [.16, .26], treeX: .86, treeL: .15, blossom: true}); };
  SCN.orchard = function (s, P) { return gardenScene(s, P, {seed: 29, flowers: Math.max(5, Math.round(s.w / 75)), fh: [.08, .16], treeX: .5, treeL: .2, blossom: true}); };

  // La Nuit: from sunset to night, the moon rises
  SCN.sky = function (s, P) {
    var R = rng(5), st = [], cl = [], shoot = {t: -9};
    for (var i = 0; i < 260; i++) st.push({x: R(), y: R() * .85, z: .2 + R() * .8, ph: R() * TAU});
    for (var j = 0; j < 6; j++) cl.push({x: R(), y: .12 + R() * .45, w: .3 + R() * .4, v: .004 + R() * .006});
    var duskTop = mix(P.bg, [92, 70, 140], .55), duskBot = P.soft, nightTop = mix(P.bg, P.black, .35), nightBot = mix(P.bg, P.accent, .12), moon = moonImage();
    return function (g, w, h, t, p) {
      var k = sstep(0, .32, p);
      var gr = g.createLinearGradient(0, 0, 0, h); gr.addColorStop(0, rgb(mix(duskTop, nightTop, k))); gr.addColorStop(.7, rgb(mix(mix(duskTop, duskBot, .6), mix(nightTop, nightBot, .6), k))); gr.addColorStop(1, rgb(mix(duskBot, nightBot, k)));
      g.fillStyle = gr; g.fillRect(0, 0, w, h);
      if (k < 1) { var sy = h * (.62 + k * .55), sg = g.createRadialGradient(w * .3, sy, 0, w * .3, sy, h * .45); sg.addColorStop(0, rgb([255, 214, 150], .9 * (1 - k))); sg.addColorStop(.12, rgb([255, 170, 110], .6 * (1 - k))); sg.addColorStop(1, 'rgba(255,150,100,0)'); g.fillStyle = sg; g.fillRect(0, 0, w, h); g.fillStyle = rgb([255, 236, 200], 1 - k); g.beginPath(); g.arc(w * .3, sy, Math.min(w, h) * .07, 0, TAU); g.fill(); }
      st.forEach(function (q) { var a = k * (.25 + .75 * Math.abs(Math.sin(t * (.6 + q.z) + q.ph))); if (a < .02) return; g.globalAlpha = a; g.fillStyle = q.z > .85 ? rgb(mix(P.accent, P.white, .4)) : '#fff'; g.beginPath(); g.arc(q.x * w, (q.y * h - p * h * .15 * q.z + h) % h, q.z * 1.4, 0, TAU); g.fill(); });
      g.globalAlpha = 1;
      var mr = Math.min(w, h) * .2, my = h * (1.15 - sstep(.08, .55, p) * .92), mx = w * .68;
      var glow = g.createRadialGradient(mx, my, mr * .8, mx, my, mr * 3.2); glow.addColorStop(0, 'rgba(255,240,205,.32)'); glow.addColorStop(1, 'rgba(255,240,205,0)'); g.fillStyle = glow; g.fillRect(0, 0, w, h);
      g.drawImage(moon, mx - mr, my - mr, mr * 2, mr * 2);
      cl.forEach(function (c) { var x = ((c.x + t * c.v) % 1.6) - .3; var cg = g.createRadialGradient(x * w, c.y * h, 0, x * w, c.y * h, c.w * w * .5); var col = mix([255, 190, 170], mix(P.bg, P.white, .25), k); cg.addColorStop(0, rgb(col, .22 - k * .1)); cg.addColorStop(1, rgb(col, 0)); g.fillStyle = cg; g.beginPath(); g.ellipse(x * w, c.y * h, c.w * w * .5, c.w * w * .12, 0, 0, TAU); g.fill(); });
      if (k > .6) { if (t - shoot.t > 7) shoot = {t: t, x: .1 + Math.random() * .5, y: .05 + Math.random() * .25}; var u = (t - shoot.t) / 1.1; if (u < 1) { var x1 = (shoot.x + u * .35) * w, y1 = (shoot.y + u * .15) * h; var sg2 = g.createLinearGradient(x1 - 120, y1 - 50, x1, y1); sg2.addColorStop(0, 'rgba(255,255,255,0)'); sg2.addColorStop(1, 'rgba(255,255,255,' + (1 - u) + ')'); g.strokeStyle = sg2; g.lineWidth = 2; g.beginPath(); g.moveTo(x1 - 120, y1 - 50); g.lineTo(x1, y1); g.stroke(); } }
    };
  };
  SCN.savanna = function (s, P) {
    var R = rng(8), W = s.w, H = s.h, grass = grassField(R, W, H, Math.round(W / 2.5), .03, .09), ff = [];
    for (var i = 0; i < 26; i++) ff.push({x: R(), y: .72 + R() * .25, ph: R() * TAU, v: .3 + R() * .5});
    var trees = [{x: .18, h: .3, s: 1}, {x: .84, h: .22, s: .75}, {x: .62, h: .13, s: .5}];
    var br = trees.map(function () { var b = []; for (var k = 0; k < 7; k++) b.push({a: -1.2 + k * .4 + (R() - .5) * .2, l: .25 + R() * .2, ph: R() * TAU, tw: R() < .7}); return b; });
    return function (g, w, h, t, p, gp) {
      g.clearRect(0, 0, w, h);
      var sil = rgb(mix(P.bg, P.black, .55)), k = sstep(0, .3, gp);
      g.fillStyle = sil; g.beginPath(); g.moveTo(0, h); for (var x = 0; x <= w; x += 10) g.lineTo(x, h * .86 - Math.sin(x * .01) * 8 - Math.sin(x * .031) * 4); g.lineTo(w, h); g.fill();
      trees.forEach(function (tr, i) {
        var bx = tr.x * w, by = h * .87, th = h * tr.h, tw = th * .26;
        g.fillStyle = sil; g.beginPath(); g.moveTo(bx - tw, by); g.bezierCurveTo(bx - tw * 1.25, by - th * .45, bx - tw * .55, by - th * .8, bx - tw * .35, by - th); g.lineTo(bx + tw * .35, by - th); g.bezierCurveTo(bx + tw * .55, by - th * .8, bx + tw * 1.25, by - th * .45, bx + tw, by); g.fill();
        g.strokeStyle = sil; g.lineCap = 'round';
        br[i].forEach(function (b) { var sw = Math.sin(t * .7 + b.ph) * .03, a = b.a + sw, len = th * b.l, x1 = bx + Math.sin(a) * tw * .3, y1 = by - th, x2 = x1 + Math.sin(a) * len, y2 = y1 - Math.cos(a) * len * .8; g.lineWidth = tw * .22; g.beginPath(); g.moveTo(x1, y1); g.quadraticCurveTo(x1 + Math.sin(a) * len * .3, y1 - len * .5, x2, y2); g.stroke(); if (b.tw) { g.lineWidth = tw * .08; [-.6, .5].forEach(function (d) { g.beginPath(); g.moveTo(x2, y2); g.lineTo(x2 + Math.sin(a + d + sw * 2) * len * .35, y2 - Math.cos(a + d) * len * .3); g.stroke(); }); } });
      });
      drawGrass(g, grass, h, t, sil, rgb(mix(P.bg, P.black, .4)), Math.sin(t * .4) * .5);
      ff.forEach(function (f) { var a = k * (.2 + .8 * Math.max(0, Math.sin(t * f.v * 3 + f.ph))); if (a < .03) return; var x = (f.x + Math.sin(t * .3 * f.v + f.ph) * .04) * w, y = (f.y + Math.cos(t * .4 * f.v + f.ph) * .03) * h; var fg = g.createRadialGradient(x, y, 0, x, y, 10); fg.addColorStop(0, rgb(mix(P.accent, P.white, .5), a)); fg.addColorStop(1, rgb(P.accent, 0)); g.fillStyle = fg; g.fillRect(x - 10, y - 10, 20, 20); });
    };
  };
  SCN.moonface = function (s) { var m = moonImage(); return function (g, w, h, t, p) { g.clearRect(0, 0, w, h); g.save(); g.translate(w / 2, h / 2); g.rotate(p * .6 + t * .01); g.drawImage(m, -w / 2, -h / 2, w, h); g.restore(); }; };

  // Le Pagne: a loom weaving Faso Dan Fani, thread by thread
  function pagneColors(P) { return [P.deep, P.deep, P.accent, P.white, P.red, P.red, P.white, P.deep, P.deep, P.green, P.accent, P.accent, P.white, P.deep]; }
  function weaveCloth(P, cols, rows, c, R) {
    var oc = document.createElement('canvas'); oc.width = cols * c; oc.height = rows * c; var g = oc.getContext('2d'), wc = pagneColors(P);
    var warp = []; for (var i = 0; i < cols; i++) warp.push(wc[Math.floor(i / 2) % wc.length]);
    var bands = [P.bg, P.bg, P.deep, P.accent, P.bg, P.red, P.bg, P.deep];
    for (var j = 0; j < rows; j++) {
      var motif = (j % 28) > 18, weft = bands[Math.floor(j / 3) % bands.length];
      for (var i2 = 0; i2 < cols; i2++) {
        var over = (i2 + j) % 2 === 0, col = over ? warp[i2] : weft;
        if (motif) { var m = Math.abs(((i2 % 12) - 6)) + Math.abs(((j % 28) - 23)); if (m < 4) col = m % 2 ? P.accent : P.red; else if (m === 4) col = P.white; }
        var v = .92 + R() * .16;
        g.fillStyle = rgb([col[0] * v, col[1] * v, col[2] * v]); g.fillRect(i2 * c, j * c, c, c);
        g.fillStyle = 'rgba(255,255,255,.16)'; g.fillRect(i2 * c, j * c, c, 1);
        g.fillStyle = 'rgba(0,0,0,.2)'; g.fillRect(i2 * c, j * c + c - 1, c, 1);
      }
    }
    return {cv: oc, warp: warp};
  }
  SCN.loom = function (s, P) {
    var c = 7, cols = Math.ceil(s.w / c) + 1, rows = Math.ceil(s.h / c) + 1, R = rng(17), cl = weaveCloth(P, cols, rows, c, R), woven = rows * .25;
    return function (g, w, h, t, p) {
      var target = rows * (.3 + .7 * clamp(p * 1.4));
      woven = Math.min(rows, woven + (target - woven) * .04 + .05);
      var wy = Math.floor(woven) * c;
      g.fillStyle = rgb(mix(P.deep, P.black, .4)); g.fillRect(0, 0, w, h);
      // the warp, waiting, quivering a little
      for (var i = 0; i < cols; i++) { var x = i * c + c / 2 + Math.sin(t * 2 + i) * .3; g.strokeStyle = rgb(cl.warp[i], .85); g.lineWidth = 2.2; g.beginPath(); g.moveTo(x, wy); g.lineTo(x, h); g.stroke(); }
      g.drawImage(cl.cv, 0, 0, cols * c, wy, 0, 0, cols * c, wy);
      // the reed, beating the new row in, and the shuttle crossing
      var beat = Math.max(0, Math.sin(t * 3.2)) * 6;
      g.fillStyle = rgb(mix(P.accent, P.deep, .45)); g.fillRect(0, wy + 4 + beat, w, 5);
      g.fillStyle = 'rgba(255,255,255,.25)'; g.fillRect(0, wy + 4 + beat, w, 1);
      var sx = (Math.sin(t * 1.15) * .5 + .5) * (w - 60) + 30;
      g.strokeStyle = rgb(P.bg, .8); g.lineWidth = 1.5; g.beginPath(); g.moveTo(Math.sin(t * 1.15) > 0 ? 0 : w, wy - c / 2); g.lineTo(sx, wy + 14); g.stroke();
      var sg = g.createLinearGradient(sx - 30, 0, sx + 30, 0); sg.addColorStop(0, '#6b3f1d'); sg.addColorStop(.5, '#b9773b'); sg.addColorStop(1, '#6b3f1d');
      g.fillStyle = sg; g.beginPath(); g.ellipse(sx, wy + 16, 30, 7, 0, 0, TAU); g.fill();
      var dk = g.createLinearGradient(0, 0, 0, h); dk.addColorStop(0, 'rgba(0,0,0,0)'); dk.addColorStop(1, 'rgba(0,0,0,.25)'); g.fillStyle = dk; g.fillRect(0, 0, w, h);
    };
  };
  SCN.weave = function (s, P) {
    var c = 6, R = rng(23), cl = weaveCloth(P, 168, Math.ceil(s.h / c) + 1, c, R), pw = 168 * c;
    return function (g, w, h, t, p) {
      var off = ((t * 14 + p * 500) * (s.rev ? -1 : 1)) % pw; if (off < 0) off += pw;
      for (var x = -off; x < w; x += pw) g.drawImage(cl.cv, x, 0);
    };
  };

  // Le Magazine: colours that drift behind the cover, with film grain
  SCN.blobs = function (s, P) {
    var R = rng(31), bl = [], gn = document.createElement('canvas'); gn.width = gn.height = 128; var gg = gn.getContext('2d'), id = gg.createImageData(128, 128);
    for (var i = 0; i < id.data.length; i += 4) { var v = R() * 255; id.data[i] = id.data[i + 1] = id.data[i + 2] = v; id.data[i + 3] = 26; }
    gg.putImageData(id, 0, 0);
    var cs = [P.accent, P.soft, mix(P.accent, P.white, .5), mix(P.deep, P.accent, .5), P.soft];
    for (var j = 0; j < 5; j++) bl.push({c: cs[j], ph: R() * TAU, sp: .08 + R() * .1, r: .45 + R() * .35, ax: .3 + R() * .3, ay: .2 + R() * .3});
    var pat = null;
    return function (g, w, h, t, p) {
      g.fillStyle = rgb(P.bg); g.fillRect(0, 0, w, h);
      bl.forEach(function (b, i) { var x = w * (.5 + b.ax * Math.sin(t * b.sp + b.ph)), y = h * (.45 + b.ay * Math.cos(t * b.sp * 1.3 + b.ph) - p * .3), r = Math.max(w, h) * b.r * (1 + p * .3); var gr = g.createRadialGradient(x, y, 0, x, y, r); gr.addColorStop(0, rgb(b.c, i === 3 ? .35 : .55)); gr.addColorStop(1, rgb(b.c, 0)); g.fillStyle = gr; g.fillRect(0, 0, w, h); });
      if (!pat) pat = g.createPattern(gn, 'repeat');
      g.save(); g.translate((Math.random() * 128) | 0, (Math.random() * 128) | 0); g.fillStyle = pat; g.fillRect(-128, -128, w + 256, h + 256); g.restore();
    };
  };

  // Le Blason: velvet curtains open on light and gold
  SCN.velvet = function (s, P) {
    var R = rng(13), sp = [], cv = mix(mix(P.deep, [120, 18, 34], .55), P.black, .15);
    for (var i = 0; i < 50; i++) sp.push({x: R(), y: R(), s: 2 + R() * 4, ph: R() * TAU, v: .004 + R() * .008});
    return function (g, w, h, t, p) {
      g.clearRect(0, 0, w, h);
      g.save(); g.translate(w / 2, -h * .05); g.rotate(t * .03);
      for (var r = 0; r < 14; r++) { g.rotate(TAU / 14); var rg = g.createLinearGradient(0, 0, 0, h * 1.2); rg.addColorStop(0, rgb(P.accent, .16)); rg.addColorStop(1, rgb(P.accent, 0)); g.fillStyle = rg; g.beginPath(); g.moveTo(0, 0); g.lineTo(-w * .08, h * 1.2); g.lineTo(w * .08, h * 1.2); g.fill(); }
      g.restore();
      sp.forEach(function (q) { var y = ((q.y - t * q.v) % 1 + 1) % 1, a = Math.abs(Math.sin(t * 1.6 + q.ph)), x = q.x * w, yy = y * h, z = q.s * a; g.fillStyle = rgb(mix(P.accent, P.white, .5), a); g.beginPath(); g.moveTo(x, yy - z * 2); g.lineTo(x + z * .5, yy - z * .5); g.lineTo(x + z * 2, yy); g.lineTo(x + z * .5, yy + z * .5); g.lineTo(x, yy + z * 2); g.lineTo(x - z * .5, yy + z * .5); g.lineTo(x - z * 2, yy); g.lineTo(x - z * .5, yy - z * .5); g.fill(); });
      var open = clamp(ease((t - .3) / 2.4) * .62 + p * .9), half = w / 2 * (1 - open * .92);
      [0, 1].forEach(function (side) {
        for (var x = 0; x < half; x += 3) {
          var u = x / Math.max(1, half), fold = .5 + .5 * Math.sin(u * 22 + Math.sin(t * .8 + u * 3) * .6 + side), sh = .55 + fold * .45;
          var col = mix(mix(cv, P.black, .45), mix(cv, P.white, .12), fold);
          var X = side ? w - x - 3 : x, sag = Math.sin(u * Math.PI) * 10 * open;
          g.fillStyle = rgb(col); g.fillRect(X, 0, 3.4, h - sag);
          void sh;
        }
        var ex = side ? w - half : half; g.fillStyle = rgb(P.accent); g.fillRect(ex - 2, 0, 4, h);
      });
      g.fillStyle = rgb(mix(cv, P.black, .25));
      g.beginPath(); g.moveTo(0, 0); g.lineTo(w, 0); g.lineTo(w, 34); for (var k = 8; k >= 0; k--) { var x0 = k / 8 * w; g.quadraticCurveTo(x0 + w / 16, 62, x0, 34); } g.fill();
      g.strokeStyle = rgb(P.accent); g.lineWidth = 2; g.beginPath(); g.moveTo(w, 34); for (var k2 = 8; k2 >= 0; k2--) { var x1 = k2 / 8 * w; g.quadraticCurveTo(x1 + w / 16, 62, x1, 34); } g.stroke();
    };
  };

  // Le Carnet: balloons rise, confetti falls
  SCN.party = function (s, P) {
    var R = rng(19), bl = [], cf = [], cs = [P.accent, P.soft, mix(P.accent, P.white, .4), mix(P.accent, P.deep, .3), [255, 210, 90]];
    for (var i = 0; i < 8; i++) bl.push({x: .06 + R() * .88, off: R(), sp: .03 + R() * .03, r: 22 + R() * 14, c: cs[i % cs.length], ph: R() * TAU});
    for (var j = 0; j < 90; j++) cf.push({x: R(), y: -R() * 1.2, vy: .05 + R() * .08, ph: R() * TAU, c: cs[(R() * 5) | 0], s: 4 + R() * 5});
    return function (g, w, h, t, p) {
      g.clearRect(0, 0, w, h);
      bl.forEach(function (b) {
        var y = h + 80 - ((b.off + t * b.sp + p * .6) % 1.25) * (h + 220), x = b.x * w + Math.sin(t * .8 + b.ph) * 16;
        g.strokeStyle = 'rgba(80,70,60,.5)'; g.lineWidth = 1; g.beginPath(); g.moveTo(x, y + b.r * 1.2); g.bezierCurveTo(x + Math.sin(t * 1.4 + b.ph) * 14, y + b.r * 2.2, x - Math.sin(t * 1.1 + b.ph) * 14, y + b.r * 3, x + Math.sin(t + b.ph) * 6, y + b.r * 4);
        g.stroke();
        var gr = g.createRadialGradient(x - b.r * .35, y - b.r * .4, b.r * .1, x, y, b.r * 1.25); gr.addColorStop(0, rgb(mix(b.c, P.white, .55))); gr.addColorStop(.6, rgb(b.c)); gr.addColorStop(1, rgb(mix(b.c, P.black, .25)));
        g.fillStyle = gr; g.beginPath(); g.ellipse(x, y, b.r, b.r * 1.2, Math.sin(t + b.ph) * .08, 0, TAU); g.fill();
        g.fillStyle = rgb(mix(b.c, P.black, .25)); g.beginPath(); g.moveTo(x - 4, y + b.r * 1.25); g.lineTo(x + 4, y + b.r * 1.25); g.lineTo(x, y + b.r * 1.12); g.fill();
        g.fillStyle = 'rgba(255,255,255,.55)'; g.beginPath(); g.ellipse(x - b.r * .38, y - b.r * .45, b.r * .14, b.r * .26, -.5, 0, TAU); g.fill();
      });
      cf.forEach(function (c) { var y = ((c.y + t * c.vy + p * .5) % 1.3) - .1, x = c.x + Math.sin(t * 1.3 + c.ph) * .02, flip = Math.cos(t * 4 + c.ph); g.save(); g.translate(x * w, y * h); g.rotate(t * 2 + c.ph); g.scale(1, flip); g.fillStyle = rgb(c.c, .9); g.fillRect(-c.s / 2, -c.s / 4, c.s, c.s / 2); g.restore(); });
    };
  };

  // ---- thirteen more living scenes ----
  function petal5(g, x, y, r, open, col, inner, rot) {
    g.save(); g.translate(x, y); g.rotate(rot); var rr = r * (.35 + .65 * open);
    g.fillStyle = col;
    for (var i = 0; i < 5; i++) { g.save(); g.rotate(i / 5 * TAU); g.beginPath(); g.moveTo(0, 0); g.bezierCurveTo(rr * .7, -rr * .3, rr * .55, -rr * 1.05, .06 * rr, -rr); g.lineTo(-.06 * rr, -rr * .9); g.bezierCurveTo(-rr * .55, -rr * 1.05, -rr * .7, -rr * .3, 0, 0); g.fill(); g.restore(); }
    g.fillStyle = inner; g.beginPath(); g.arc(0, 0, rr * .22, 0, TAU); g.fill(); g.restore();
  }
  function bird(g, x, y, s, flap, col) { g.strokeStyle = col; g.lineWidth = Math.max(1, s * .14); g.beginPath(); g.moveTo(x - s, y - flap * s * .5); g.quadraticCurveTo(x - s * .45, y - s * .25 - flap * s * .2, x, y); g.quadraticCurveTo(x + s * .45, y - s * .25 - flap * s * .2, x + s, y - flap * s * .5); g.stroke(); }
  function skyGrad(g, w, h, stops) { var gr = g.createLinearGradient(0, 0, 0, h); stops.forEach(function (s) { gr.addColorStop(s[0], rgb(s[1])); }); g.fillStyle = gr; g.fillRect(0, 0, w, h); }
  function glowDot(g, x, y, r, col, a) { var gr = g.createRadialGradient(x, y, 0, x, y, r); gr.addColorStop(0, rgb(col, a)); gr.addColorStop(1, rgb(col, 0)); g.fillStyle = gr; g.fillRect(x - r, y - r, r * 2, r * 2); }
  function ridge(g, w, y0, amp, f, ph, col) { g.fillStyle = col; g.beginPath(); g.moveTo(0, 99999); g.lineTo(0, y0); for (var x = 0; x <= w + 8; x += 8) g.lineTo(x, y0 - Math.sin(x * f + ph) * amp - Math.sin(x * f * 2.7 + ph * 1.3) * amp * .35); g.lineTo(w, 99999); g.fill(); }

  // Sahel: a golden afternoon turning to sunset; acacias, a giraffe, birds, waves of grass
  SCN.sahel = function (s, P) {
    var R = rng(51), grass = [], trees = [{x: .16, s: 1.15}, {x: .7, s: .8}, {x: .94, s: .5}], fl = [];
    for (var i = 0; i < Math.round(s.w / 2); i++) grass.push({x: R() * s.w, h: .07 + R() * .13, ph: R() * TAU});
    trees.forEach(function (t) { t.c = []; for (var k = 0; k < 30; k++) t.c.push({x: (R() - .5) * 2, y: (R() - .5) * .3, r: .18 + R() * .2}); });
    for (var f = 0; f < 3; f++) fl.push({o: R(), y: .12 + R() * .2, n: 4 + (R() * 3 | 0), sp: .012 + R() * .01});
    return function (g, w, h, t, p) {
      var k = sstep(0, .9, p);
      skyGrad(g, w, h, [[0, mix([110, 165, 205], [70, 55, 115], k)], [.5, mix([240, 215, 165], [236, 140, 95], k)], [.75, mix([250, 228, 175], [250, 175, 110], k)], [1, [120, 80, 40]]]);
      var sy = h * (.18 + .44 * k), sx = w * .68, sr = Math.min(w, h) * .085;
      glowDot(g, sx, sy, sr * 6, mix([255, 240, 200], [255, 150, 80], k), .5); g.fillStyle = rgb(mix([255, 248, 220], [255, 170, 90], k)); g.beginPath(); g.arc(sx, sy, sr, 0, TAU); g.fill();
      ridge(g, w, h * .66, 12, .006, 1, rgb(mix([205, 170, 125], [150, 92, 85], k), .7));
      var gr = g.createLinearGradient(0, h * .7, 0, h); gr.addColorStop(0, rgb(mix([214, 168, 86], [190, 110, 60], k))); gr.addColorStop(1, rgb(mix([150, 105, 45], [90, 50, 30], k))); g.fillStyle = gr; g.fillRect(0, h * .72, w, h);
      var sil = rgb(mix([86, 64, 38], [45, 26, 28], k));
      trees.forEach(function (tr) {
        var bx = tr.x * w, by = h * .74, th = h * .2 * tr.s, cw = w * .2 * tr.s, sw = Math.sin(t * .6 + tr.x * 9) * 3 * tr.s;
        g.strokeStyle = sil; g.lineCap = 'round'; g.lineWidth = 7 * tr.s;
        g.beginPath(); g.moveTo(bx, by); g.quadraticCurveTo(bx - 6, by - th * .5, bx + sw * .5, by - th); g.stroke();
        g.lineWidth = 3 * tr.s; [-1, -.4, .5, 1].forEach(function (d) { g.beginPath(); g.moveTo(bx + sw * .5, by - th * .9); g.lineTo(bx + d * cw * .45 + sw, by - th - 6 * tr.s); g.stroke(); });
        g.fillStyle = sil; tr.c.forEach(function (c) { g.beginPath(); g.ellipse(bx + sw + c.x * cw * .5, by - th - 10 * tr.s + c.y * cw * .3, c.r * cw * .5, c.r * cw * .16, 0, 0, TAU); g.fill(); });
      });
      // a giraffe walking slowly across
      var gx = ((t * .01 + .3) % 1.5 - .25) * w, gy = h * .745, gs = h * .0011 * 60, step = Math.sin(t * 2.4);
      g.fillStyle = sil; g.strokeStyle = sil; g.lineCap = 'round';
      g.beginPath(); g.ellipse(gx, gy - gs * 2.1, gs * 1.1, gs * .55, -.1, 0, TAU); g.fill();
      g.lineWidth = gs * .32; g.beginPath(); g.moveTo(gx + gs * .8, gy - gs * 2.3); g.lineTo(gx + gs * 1.5 + Math.sin(t * .8) * gs * .1, gy - gs * 4.2); g.stroke();
      g.beginPath(); g.ellipse(gx + gs * 1.7, gy - gs * 4.25, gs * .38, gs * .17, .3, 0, TAU); g.fill();
      g.lineWidth = gs * .16; [[-.7, 1], [-.45, -1], [.55, -1], [.8, 1]].forEach(function (l) { var sw2 = step * l[1] * gs * .35; g.beginPath(); g.moveTo(gx + l[0] * gs, gy - gs * 1.9); g.lineTo(gx + l[0] * gs + sw2, gy); g.stroke(); });
      fl.forEach(function (f) { var bx = ((t * f.sp + f.o) % 1.3 - .15) * w; for (var b = 0; b < f.n; b++) bird(g, bx - b * 16, h * f.y + Math.abs(b - f.n / 2) * 7, 7, Math.sin(t * 7 + b), sil); });
      g.strokeStyle = rgb(mix([235, 190, 100], [205, 120, 60], k)); g.lineWidth = 1.4; g.beginPath();
      grass.forEach(function (b) { var hh = h * b.h, sw = Math.sin(t * 1.5 - b.x * .012 + b.ph * .2) * hh * .22; g.moveTo(b.x, h); g.quadraticCurveTo(b.x + sw * .3, h - hh * .5, b.x + sw, h - hh); }); g.stroke();
    };
  };

  // Océan: sunset on the sea, waves, a palm tree, gulls
  SCN.ocean = function (s, P) {
    var R = rng(61), gulls = []; for (var i = 0; i < 4; i++) gulls.push({o: R(), y: .12 + R() * .22, sp: .015 + R() * .015, s: 6 + R() * 6});
    var fr = []; for (var j = 0; j < 9; j++) fr.push({a: -2.6 + j * .6 + (R() - .5) * .2, l: .7 + R() * .4, ph: R() * TAU});
    return function (g, w, h, t, p) {
      var hz = h * .56, k = clamp(p);
      skyGrad(g, w, h, [[0, mix(mix(P.deep, [60, 70, 130], .5), [40, 30, 80], k)], [.45, mix([245, 160, 120], [220, 110, 110], k)], [.56, mix([255, 210, 150], [250, 150, 100], k)], [1, [30, 40, 70]]]);
      var sr = Math.min(w, h) * .1, sy = hz - sr * (1.4 - k * 1.3);
      glowDot(g, w * .5, sy, sr * 5, [255, 200, 140], .55); g.save(); g.beginPath(); g.rect(0, 0, w, hz); g.clip(); g.fillStyle = 'rgb(255,226,170)'; g.beginPath(); g.arc(w * .5, sy, sr, 0, TAU); g.fill(); g.restore();
      for (var L = 0; L < 7; L++) {
        var y0 = hz + (h - hz) * Math.pow(L / 7, 1.5), amp = 2 + L * 3, col = mix(mix(P.deep, [20, 60, 90], .5), mix(P.accent, [80, 150, 170], .5), 1 - L / 7);
        g.fillStyle = rgb(mix(col, [250, 170, 120], (1 - L / 7) * .35));
        g.beginPath(); g.moveTo(0, h); for (var x = 0; x <= w + 10; x += 10) g.lineTo(x, y0 + Math.sin(x * (.02 - L * .002) + t * (.8 + L * .25) + L) * amp + Math.sin(x * .007 - t * .5) * amp * .6); g.lineTo(w, h); g.fill();
        g.strokeStyle = 'rgba(255,245,230,' + (.08 + L * .03) + ')'; g.lineWidth = 1 + L * .3; g.beginPath(); for (var x2 = 0; x2 <= w + 10; x2 += 10) { var yy = y0 + Math.sin(x2 * (.02 - L * .002) + t * (.8 + L * .25) + L) * amp + Math.sin(x2 * .007 - t * .5) * amp * .6; x2 ? g.lineTo(x2, yy) : g.moveTo(x2, yy); } g.stroke();
      }
      for (var r = 0; r < 26; r++) { var ry = hz + 4 + r * (h - hz) / 28, rw = sr * (1.2 - r / 32) * (.6 + .4 * Math.abs(Math.sin(t * 2 + r * 1.7))); g.fillStyle = 'rgba(255,225,170,' + (.55 - r * .018) + ')'; g.fillRect(w * .5 - rw + Math.sin(t * 1.3 + r) * 8, ry, rw * 2, 2); }
      var px = w * .1, py = h, ph = h * .55, sw = Math.sin(t * .7) * 10, tx = px + w * .18 + sw, ty = py - ph;
      g.strokeStyle = '#1c1410'; g.lineCap = 'round'; g.lineWidth = 12; g.beginPath(); g.moveTo(px, py); g.quadraticCurveTo(px + w * .02, py - ph * .6, tx, ty); g.stroke();
      fr.forEach(function (f) { var a = f.a + Math.sin(t * 1.2 + f.ph) * .07, L2 = h * .17 * f.l, ex = tx + Math.cos(a) * L2, ey = ty + Math.sin(a) * L2 * .6 + L2 * .35; g.lineWidth = 3; g.beginPath(); g.moveTo(tx, ty); g.quadraticCurveTo(tx + Math.cos(a) * L2 * .5, ty + Math.sin(a) * L2 * .5 - 12, ex, ey); g.stroke(); g.lineWidth = 1.4; for (var q = 1; q < 9; q++) { var u = q / 9, qx = tx + (ex - tx) * u, qy = ty + (ey - ty) * u - Math.sin(u * Math.PI) * 10; g.beginPath(); g.moveTo(qx, qy); g.lineTo(qx + Math.cos(a + 1.4) * 14 * (1 - u * .5), qy + Math.sin(a + 1.4) * 14 * (1 - u * .5) + 6); g.moveTo(qx, qy); g.lineTo(qx + Math.cos(a - 1.4) * 14 * (1 - u * .5), qy + Math.sin(a - 1.4) * 14 * (1 - u * .5) + 6); g.stroke(); } });
      gulls.forEach(function (q) { bird(g, ((t * q.sp + q.o) % 1.3 - .15) * w, h * q.y + Math.sin(t + q.o * 9) * 6, q.s, Math.sin(t * 6 + q.o * 20), 'rgba(40,30,40,.75)'); });
    };
  };

  // Lotus: a pond seen from above, ripples, pads, opening lotuses, koi
  SCN.lotus = function (s, P) {
    var R = rng(71), pads = [], koi = [], rip = [], last = 0;
    for (var i = 0; i < 10; i++) pads.push({x: R(), y: R(), r: 26 + R() * 34, a: R() * TAU, d: .3 + R() * .7, fl: i % 3 === 0, ph: R() * TAU});
    for (var j = 0; j < 4; j++) koi.push({cx: .2 + R() * .6, cy: .2 + R() * .6, rx: .2 + R() * .2, ry: .15 + R() * .2, sp: .08 + R() * .07, ph: R() * TAU, s: 16 + R() * 10, c: j % 2 ? [245, 120, 40] : [250, 245, 235]});
    return function (g, w, h, t, p) {
      var gr = g.createRadialGradient(w * .4, h * .3, 0, w * .5, h * .5, Math.max(w, h)); gr.addColorStop(0, rgb(mix(P.soft, [40, 110, 110], .55))); gr.addColorStop(1, rgb(mix(P.deep, [8, 40, 45], .6))); g.fillStyle = gr; g.fillRect(0, 0, w, h);
      for (var c = 0; c < 9; c++) glowDot(g, w * (.5 + .45 * Math.sin(t * .1 + c * 2)), h * (.5 + .45 * Math.cos(t * .13 + c * 1.3)), w * .3, [200, 240, 230], .05);
      if (t - last > .6) { last = t; rip.push({x: Math.random() * w, y: Math.random() * h, t: t}); if (rip.length > 8) rip.shift(); }
      rip.forEach(function (r) { var a = (t - r.t) / 4; if (a > 1) return; g.strokeStyle = 'rgba(230,255,250,' + (.35 * (1 - a)) + ')'; g.lineWidth = 1.2; for (var q = 0; q < 3; q++) { var rr = (a * 90) - q * 14; if (rr > 0) { g.beginPath(); g.ellipse(r.x, r.y, rr, rr * .8, 0, 0, TAU); g.stroke(); } } });
      koi.forEach(function (f) {
        var a = t * f.sp * TAU * .3 + f.ph, x = w * (f.cx + Math.cos(a) * f.rx), y = h * (f.cy + Math.sin(a * 1.3) * f.ry);
        var dx = -Math.sin(a) * f.rx * w, dy = Math.cos(a * 1.3) * 1.3 * f.ry * h, hd = Math.atan2(dy, dx);
        g.save(); g.translate(x, y); g.rotate(hd); g.globalAlpha = .9;
        for (var sgm = 7; sgm >= 0; sgm--) { var u = sgm / 7, ox = -u * f.s * 2.2, oy = Math.sin(t * 5 - u * 3) * f.s * .18 * u, rr = f.s * .42 * (1 - u * .75); g.fillStyle = rgb(sgm % 3 === 1 ? [250, 248, 240] : f.c); g.beginPath(); g.ellipse(ox, oy, rr * 1.2, rr, 0, 0, TAU); g.fill(); }
        g.fillStyle = rgb(f.c, .7); var tl = Math.sin(t * 5 - 3) * f.s * .3; g.beginPath(); g.moveTo(-f.s * 2.1, tl * .6); g.lineTo(-f.s * 2.9, tl - f.s * .4); g.lineTo(-f.s * 2.9, tl + f.s * .4); g.fill();
        g.restore(); g.globalAlpha = 1;
      });
      pads.forEach(function (pd) {
        var x = pd.x * w + Math.sin(t * .2 + pd.ph) * 6, y = ((pd.y * h - p * h * .4 * pd.d) % h + h) % h, a = pd.a + t * .02;
        g.fillStyle = rgb(mix([60, 130, 70], P.accent, .15)); g.beginPath(); g.moveTo(x, y); g.arc(x, y, pd.r, a + .25, a + TAU - .05); g.closePath(); g.fill();
        g.strokeStyle = 'rgba(200,240,170,.35)'; g.lineWidth = 1; for (var v = 0; v < 7; v++) { var va = a + .4 + v * .85; g.beginPath(); g.moveTo(x, y); g.lineTo(x + Math.cos(va) * pd.r * .9, y + Math.sin(va) * pd.r * .9); g.stroke(); }
        if (pd.fl) {
          var op = ease((t - .4) / 3) * (.7 + .3 * clamp(p * 2));
          for (var L = 0; L < 3; L++) { var n = 8, rr2 = pd.r * (.85 - L * .22) * (.4 + .6 * op); for (var q2 = 0; q2 < n; q2++) { var pa = q2 / n * TAU + L * .4 + t * .03; g.save(); g.translate(x, y); g.rotate(pa); var pg = g.createLinearGradient(0, 0, 0, -rr2); pg.addColorStop(0, rgb(mix(P.accent, [255, 255, 255], .7))); pg.addColorStop(1, rgb(mix(P.accent, [235, 120, 170], .5))); g.fillStyle = pg; g.beginPath(); g.moveTo(0, 0); g.quadraticCurveTo(rr2 * .5, -rr2 * .5, 0, -rr2); g.quadraticCurveTo(-rr2 * .5, -rr2 * .5, 0, 0); g.fill(); g.restore(); } }
          g.fillStyle = 'rgb(250,220,90)'; g.beginPath(); g.arc(x, y, pd.r * .14, 0, TAU); g.fill();
        }
      });
    };
  };

  // Forêt: a misty forest you walk into; light rays, fog, motes, ferns
  SCN.forest = function (s, P) {
    var R = rng(81), layers = [];
    for (var L = 0; L < 5; L++) { var tr = []; for (var i = 0; i < 9 + L * 2; i++) tr.push({x: R() * 1.3 - .15, h: .35 + R() * .4, w: .05 + R() * .04 + L * .01}); layers.push(tr); }
    var motes = []; for (var m = 0; m < 50; m++) motes.push({x: R(), y: R(), v: .005 + R() * .01, ph: R() * TAU});
    return function (g, w, h, t, p) {
      var fog = mix(P.soft, [220, 232, 225], .4), dark = mix(P.deep, [12, 30, 22], .5);
      skyGrad(g, w, h, [[0, mix(fog, [255, 250, 235], .4)], [1, fog]]);
      g.save(); g.translate(w * .82, -h * .1); g.rotate(.32 + Math.sin(t * .1) * .03);
      for (var r = 0; r < 7; r++) { var a = .25 + .15 * Math.sin(t * .4 + r); var rg = g.createLinearGradient(0, 0, 0, h * 1.4); rg.addColorStop(0, 'rgba(255,248,220,' + a * .5 + ')'); rg.addColorStop(1, 'rgba(255,248,220,0)'); g.fillStyle = rg; g.fillRect(-w * .5 + r * w * .16, 0, w * .05, h * 1.4); }
      g.restore();
      layers.forEach(function (tr, L) {
        var z = 1 + p * (.05 + L * .07), col = mix(fog, dark, Math.pow((L + 1) / 6, 1.6) * .9), base = h * (.82 + L * .045);
        g.save(); g.translate(w / 2, base); g.scale(z, z); g.translate(-w / 2, -base);
        g.fillStyle = rgb(col);
        tr.forEach(function (q) { var x = q.x * w, th = h * q.h, tw = w * q.w, sw = Math.sin(t * .5 + q.x * 7) * 2 * (L + 1) * .3; g.fillRect(x - tw * .12, base - th, tw * .24, th); for (var k = 0; k < 6; k++) { var ky = base - th * (.35 + k * .11), kw = tw * (1.6 - k * .22); g.beginPath(); g.moveTo(x - kw + sw * .5, ky); g.lineTo(x + sw, ky - th * .2); g.lineTo(x + kw + sw * .5, ky); g.fill(); } });
        g.fillRect(0, base, w, h);
        g.restore();
        var fy = base - h * .05; g.fillStyle = rgb(fog, .35); g.beginPath(); g.ellipse(((t * (.01 + L * .004) + L * .3) % 1.6 - .3) * w, fy, w * .6, h * .04, 0, 0, TAU); g.fill();
      });
      motes.forEach(function (q) { var y = ((q.y - t * q.v) % 1 + 1) % 1, x = q.x + Math.sin(t * .5 + q.ph) * .02; glowDot(g, x * w, y * h, 5, [255, 245, 200], .5 * Math.abs(Math.sin(t + q.ph))); });
      [[0, 1], [w, -1]].forEach(function (fe) { for (var f = 0; f < 6; f++) { var a = -Math.PI / 2 + fe[1] * (.3 + f * .18) + Math.sin(t * .9 + f) * .05, L2 = h * (.18 + f * .02), x0 = fe[0], y0 = h; g.strokeStyle = rgb(dark); g.lineWidth = 2; var ex = x0 + Math.cos(a) * L2, ey = y0 + Math.sin(a) * L2; g.beginPath(); g.moveTo(x0, y0); g.quadraticCurveTo(x0 + Math.cos(a) * L2 * .6, y0 + Math.sin(a) * L2 * .4, ex, ey); g.stroke(); g.fillStyle = rgb(dark); for (var q2 = 1; q2 < 12; q2++) { var u = q2 / 12, qx = x0 + (ex - x0) * u, qy = y0 + (ey - y0) * u; g.beginPath(); g.ellipse(qx, qy, 10 * (1 - u * .7), 3, a + 1.2, 0, TAU); g.ellipse(qx, qy, 10 * (1 - u * .7), 3, a - 1.2, 0, TAU); g.fill(); } } });
    };
  };

  // Cerisiers: a blossoming branch and petals carried by the wind
  SCN.sakura = function (s, P) {
    var R = rng(91), tree = makeTree(R, 5, .6), pet = [];
    for (var i = 0; i < 46; i++) pet.push({x: R(), y: R(), s: 4 + R() * 5, ph: R() * TAU, v: .5 + R()});
    return function (g, w, h, t, p) {
      skyGrad(g, w, h, [[0, mix(P.bg, [255, 255, 255], .4)], [1, mix(P.soft, P.bg, .3)]]);
      ridge(g, w, h * .86, 14, .005, 2, rgb(mix(P.soft, P.accent, .2), .5));
      var open = ease((t - .2) / 3) * (.75 + .25 * clamp(p * 2)), wind = .6 + .4 * Math.sin(t * .3);
      g.save(); g.translate(-w * .04, h * .02); g.rotate(2.1 + Math.sin(t * .4) * .01);
      (function rec(n, x, y, ang, len, wd) {
        var a = ang + n.a + Math.sin(t * 1.1 + n.ph) * .015 * (6 - n.d), x2 = x + Math.sin(a) * len, y2 = y - Math.cos(a) * len;
        g.strokeStyle = rgb(mix(P.deep, [60, 40, 35], .5)); g.lineWidth = Math.max(1, wd); g.lineCap = 'round'; g.beginPath(); g.moveTo(x, y); g.lineTo(x2, y2); g.stroke();
        if (n.d <= 1) for (var b = 0; b < 4; b++) petal5(g, x2 + Math.sin(n.ph * 5 + b * 2) * len * .5, y2 + Math.cos(n.ph * 3 + b) * len * .5, 7 + (n.ph * 3 % 4), open, rgb(mix(P.accent, [255, 255, 255], .35 + (b % 2) * .2), .95), rgb(mix(P.accent, P.deep, .4)), n.ph + b);
        n.k.forEach(function (c) { rec(c, x2, y2, a, len * c.l, wd * .66); });
      })(tree, 0, 0, 0, Math.min(w, h) * .3, 14);
      g.restore();
      pet.forEach(function (q) { var x = ((q.x + t * .03 * q.v * wind + p * .2) % 1.2) - .1, y = ((q.y + t * .025 * q.v) % 1.1) - .05, fl = Math.cos(t * 3 * q.v + q.ph); g.save(); g.translate(x * w, y * h); g.rotate(t * q.v + q.ph); g.scale(1, fl); g.fillStyle = rgb(mix(P.accent, [255, 255, 255], .45), .85); g.beginPath(); g.ellipse(0, 0, q.s, q.s * .55, 0, 0, TAU); g.fill(); g.restore(); });
    };
  };

  // Tournesols: a field of sunflowers that turn to follow the sun as you scroll
  SCN.sunflowers = function (s, P) {
    var R = rng(101), fl = [], cl = [], bees = [];
    for (var row = 0; row < 4; row++) for (var i = 0; i < 5 + row * 2; i++) fl.push({x: (i + .5 + (R() - .5) * .5) / (5 + row * 2), row: row, ph: R() * TAU});
    fl.sort(function (a, b) { return b.row - a.row; });
    for (var c = 0; c < 5; c++) cl.push({x: R(), y: .08 + R() * .3, s: .2 + R() * .25, v: .004 + R() * .006});
    for (var b = 0; b < 4; b++) bees.push({ph: R() * TAU, cx: R(), cy: .4 + R() * .3});
    return function (g, w, h, t, p) {
      var a = Math.PI * (.12 + .76 * clamp(p)), sx = w * (.5 - .46 * Math.cos(a)), sy = h * (.62 - .5 * Math.sin(a)), late = Math.abs(p - .5) * 2;
      skyGrad(g, w, h, [[0, mix([90, 160, 225], [120, 120, 190], late * .6)], [.7, mix([200, 225, 245], [250, 200, 160], late * .7)], [1, [230, 220, 180]]]);
      glowDot(g, sx, sy, Math.min(w, h) * .5, [255, 245, 200], .6); g.fillStyle = 'rgb(255,246,215)'; g.beginPath(); g.arc(sx, sy, Math.min(w, h) * .07, 0, TAU); g.fill();
      cl.forEach(function (q) { var x = ((q.x + t * q.v) % 1.4 - .2) * w; g.fillStyle = 'rgba(255,255,255,.85)'; [0, .3, .6].forEach(function (o, i) { g.beginPath(); g.ellipse(x + o * q.s * w * .5, q.y * h - (i === 1 ? q.s * w * .06 : 0), q.s * w * .22, q.s * w * .1, 0, 0, TAU); g.fill(); }); });
      ridge(g, w, h * .62, 10, .008, 3, 'rgb(120,150,80)');
      fl.forEach(function (f) {
        var sc = [1.5, 1, .7, .45][f.row], x = f.x * w, gy = h * (.98 - f.row * .09), stemH = h * .22 * sc + 30, hx = x + Math.sin(t * .8 + f.ph) * 4 * sc, hy = gy - stemH;
        var face = Math.atan2(sy - hy, sx - hx), turn = Math.cos(face) * .35, R2 = 26 * sc;
        g.strokeStyle = 'rgb(70,110,45)'; g.lineWidth = 3 * sc; g.beginPath(); g.moveTo(x, gy + 20); g.quadraticCurveTo(x, gy - stemH * .5, hx, hy); g.stroke();
        g.fillStyle = 'rgb(80,125,50)'; g.beginPath(); g.ellipse(x - 10 * sc, gy - stemH * .45, 14 * sc, 6 * sc, .5, 0, TAU); g.ellipse(x + 10 * sc, gy - stemH * .6, 14 * sc, 6 * sc, -.5, 0, TAU); g.fill();
        g.save(); g.translate(hx + turn * R2 * .4, hy + Math.sin(face) * R2 * .15); g.scale(.72 + .28 * Math.abs(Math.sin(face + Math.PI / 2)) , 1);
        for (var q = 0; q < 20; q++) { var pa = q / 20 * TAU + f.ph; g.save(); g.rotate(pa); g.fillStyle = q % 2 ? 'rgb(250,196,30)' : 'rgb(255,214,60)'; g.beginPath(); g.ellipse(0, -R2 * .95, R2 * .2, R2 * .5, 0, 0, TAU); g.fill(); g.restore(); }
        var cg = g.createRadialGradient(-R2 * .1, -R2 * .1, 0, 0, 0, R2 * .6); cg.addColorStop(0, 'rgb(120,70,20)'); cg.addColorStop(1, 'rgb(60,35,15)'); g.fillStyle = cg; g.beginPath(); g.arc(0, 0, R2 * .58, 0, TAU); g.fill();
        if (f.row < 2) { g.fillStyle = 'rgba(200,140,60,.55)'; for (var sd = 0; sd < 60; sd++) { var ra = Math.sqrt(sd / 60) * R2 * .52, an = sd * 2.39996; g.fillRect(Math.cos(an) * ra, Math.sin(an) * ra, 1.6, 1.6); } }
        g.restore();
      });
      bees.forEach(function (bz) { var x = w * (bz.cx + .1 * Math.sin(t * 1.7 + bz.ph)), y = h * (bz.cy + .05 * Math.sin(t * 3.1 + bz.ph)); g.fillStyle = 'rgb(240,190,40)'; g.beginPath(); g.ellipse(x, y, 5, 3.5, 0, 0, TAU); g.fill(); g.fillStyle = 'rgba(255,255,255,.7)'; var fl2 = Math.abs(Math.sin(t * 30 + bz.ph)); g.beginPath(); g.ellipse(x - 1, y - 4, 3, 4 * fl2 + .5, 0, 0, TAU); g.fill(); g.fillStyle = '#222'; g.fillRect(x - 1, y - 3, 1.5, 6); });
    };
  };

  // Lanternes: sky lanterns released over the water, more and more as you scroll
  SCN.lanterns = function (s, P) {
    var R = rng(111), L = [], st = []; for (var i = 0; i < 70; i++) L.push({x: R(), o: R(), sp: .012 + R() * .012, s: .7 + R() * .6, ph: R() * TAU});
    for (var j = 0; j < 160; j++) st.push({x: R(), y: R() * .7, z: R(), ph: R() * TAU});
    return function (g, w, h, t, p) {
      var hz = h * .76;
      skyGrad(g, w, h, [[0, mix(P.bg, [15, 15, 45], .5)], [.6, mix(P.bg, [70, 40, 90], .5)], [.76, mix([230, 130, 90], P.accent, .3)], [1, mix(P.bg, [10, 10, 30], .5)]]);
      st.forEach(function (q) { g.globalAlpha = .3 + .7 * Math.abs(Math.sin(t * (.5 + q.z) + q.ph)); g.fillStyle = '#fff'; g.fillRect(q.x * w, q.y * h, q.z * 1.6 + .4, q.z * 1.6 + .4); }); g.globalAlpha = 1;
      ridge(g, w, hz + 4, 8, .009, 1, rgb(mix(P.bg, [0, 0, 0], .5)));
      var wg = g.createLinearGradient(0, hz, 0, h); wg.addColorStop(0, rgb(mix([200, 110, 90], P.bg, .5))); wg.addColorStop(1, rgb(mix(P.bg, [0, 0, 10], .6))); g.fillStyle = wg; g.fillRect(0, hz + 8, w, h);
      var n = Math.round(10 + clamp(p) * 60);
      for (var k = 0; k < n; k++) {
        var q = L[k], life = ((q.o + t * q.sp) % 1), y = hz - life * (hz + 80), x = q.x * w + Math.sin(t * .4 + q.ph) * 18 * life, sc = q.s * (1 - life * .55) * Math.min(w, h) / 420, fl = .8 + .2 * Math.sin(t * 9 + q.ph);
        glowDot(g, x, y, 40 * sc, [255, 170, 80], .45 * fl);
        var lg = g.createLinearGradient(0, y - 14 * sc, 0, y + 14 * sc); lg.addColorStop(0, 'rgba(255,200,120,' + fl + ')'); lg.addColorStop(1, 'rgba(255,120,50,' + fl + ')'); g.fillStyle = lg;
        g.beginPath(); g.moveTo(x - 9 * sc, y - 13 * sc); g.lineTo(x + 9 * sc, y - 13 * sc); g.lineTo(x + 7 * sc, y + 12 * sc); g.lineTo(x - 7 * sc, y + 12 * sc); g.closePath(); g.fill();
        g.fillStyle = 'rgba(255,245,200,.9)'; g.beginPath(); g.arc(x, y + 10 * sc, 2.4 * sc, 0, TAU); g.fill();
        var ry = hz + (hz - y) * .35 + 10; if (ry < h) { g.fillStyle = 'rgba(255,170,90,' + (.3 * fl) + ')'; g.fillRect(x - 8 * sc + Math.sin(t * 3 + k) * 3, ry, 16 * sc, 3 * sc); }
      }
    };
  };

  // Roseraie: climbing roses that grow up the wall and bloom
  SCN.roses = function (s, P) {
    var R = rng(121), vines = [];
    for (var i = 0; i < 6; i++) { var x0 = (i + .5) / 6, pts = [], y = 1.05, x = x0; for (var k = 0; k < 40; k++) { pts.push([x, y]); y -= .028; x += (R() - .5) * .05 + Math.sin(k * .5 + i) * .01; } var roses = []; for (var r = 0; r < 4; r++) roses.push({u: .2 + R() * .75, ph: R() * TAU, sz: 18 + R() * 14}); vines.push({pts: pts, roses: roses, ph: R() * TAU, dl: R() * .3}); }
    return function (g, w, h, t, p) {
      var wall = mix(P.soft, [240, 225, 210], .3);
      g.fillStyle = rgb(wall); g.fillRect(0, 0, w, h);
      g.strokeStyle = rgb(mix(wall, [0, 0, 0], .06)); g.lineWidth = 1; for (var by = 0; by < h; by += 26) { g.beginPath(); g.moveTo(0, by); g.lineTo(w, by); g.stroke(); for (var bx = (by / 26 % 2) * 30; bx < w; bx += 60) { g.beginPath(); g.moveTo(bx, by); g.lineTo(bx, by + 26); g.stroke(); } }
      var gr = clamp(ease(t / 3) * .55 + p * .9);
      vines.forEach(function (v) {
        var n = Math.floor(v.pts.length * clamp(gr - v.dl * .5)); if (n < 2) return;
        g.strokeStyle = 'rgb(70,90,50)'; g.lineWidth = 3; g.lineCap = 'round'; g.beginPath();
        for (var k = 0; k < n; k++) { var q = v.pts[k], sw = Math.sin(t * .9 + v.ph + k * .2) * k * .25; k ? g.lineTo(q[0] * w + sw, q[1] * h) : g.moveTo(q[0] * w + sw, q[1] * h); } g.stroke();
        g.fillStyle = 'rgb(80,115,55)'; for (var l = 2; l < n; l += 3) { var q2 = v.pts[l], sw2 = Math.sin(t * .9 + v.ph + l * .2) * l * .25, side = l % 2 ? 1 : -1; g.save(); g.translate(q2[0] * w + sw2, q2[1] * h); g.rotate(side * .9 + Math.sin(t * 1.5 + l) * .1); g.beginPath(); g.ellipse(side * 9, 0, 10, 4.5, 0, 0, TAU); g.fill(); g.restore(); }
        v.roses.forEach(function (r) { var idx = Math.floor(r.u * v.pts.length); if (idx >= n) return; var q3 = v.pts[idx], sw3 = Math.sin(t * .9 + v.ph + idx * .2) * idx * .25, op = clamp((n - idx) / 6); flower(g, q3[0] * w + sw3, q3[1] * h, r.sz, op, rgb(mix(P.accent, [200, 20, 50], .35)), rgb(mix(P.accent, [255, 200, 210], .5)), r.ph + Math.sin(t * .6 + r.ph) * .1, 6, 5, t * .01); });
      });
      for (var d = 0; d < 14; d++) glowDot(g, w * ((d * .137 + .05) % 1), h * ((d * .291 + .1) % 1), 5, [255, 255, 255], .6 * Math.max(0, Math.sin(t * 2 + d)));
    };
  };

  // Désert: dunes, wind-blown sand, a caravan crossing; day turns to a starry night
  SCN.desert = function (s, P) {
    var R = rng(131), sand = [], st = [], ph0 = +(s.cv.dataset.phase || 0);
    for (var i = 0; i < 80; i++) sand.push({x: R(), y: .45 + R() * .5, v: .2 + R() * .5, l: 6 + R() * 18});
    for (var j = 0; j < 140; j++) st.push({x: R(), y: R() * .5, z: R(), ph: R() * TAU});
    return function (g, w, h, t, p) {
      var k = clamp(ph0 * .55 + p * .55), night = sstep(.55, .95, k);
      skyGrad(g, w, h, [[0, mix(mix([120, 170, 220], [190, 90, 90], sstep(0, .55, k)), [18, 16, 45], night)], [.55, mix(mix([250, 220, 170], [250, 150, 90], sstep(0, .55, k)), [50, 35, 70], night)], [1, [120, 70, 40]]]);
      st.forEach(function (q) { var a = night * (.3 + .7 * Math.abs(Math.sin(t * (.4 + q.z) + q.ph))); if (a < .03) return; g.globalAlpha = a; g.fillStyle = '#fff'; g.fillRect(q.x * w, q.y * h, 1.6, 1.6); }); g.globalAlpha = 1;
      var cy = h * (.2 + .35 * sstep(0, .6, k)); if (night < .9) { glowDot(g, w * .3, cy, Math.min(w, h) * .4, [255, 210, 150], .6 * (1 - night)); g.fillStyle = 'rgba(255,240,210,' + (1 - night) + ')'; g.beginPath(); g.arc(w * .3, cy, Math.min(w, h) * .07, 0, TAU); g.fill(); }
      if (night > .1) { var m = moonImage(), mr = Math.min(w, h) * .06; g.globalAlpha = night; g.drawImage(m, w * .75 - mr, h * .18 - mr, mr * 2, mr * 2); g.globalAlpha = 1; }
      var base = mix(mix(P.accent, [215, 150, 90], .5), [70, 50, 70], night * .7);
      [[.6, 22, .004, .3], [.7, 26, .005, .5], [.8, 30, .0035, .7], [.9, 24, .006, .9]].forEach(function (d, i) { ridge(g, w, h * d[0], d[1], d[2], i * 1.7 + t * .01, rgb(mix(base, [40, 25, 20], d[3] * .5))); });
      var ry = function (x) { return h * .7 - Math.sin(x * .005 + 3.4 + t * .01) * 26 - Math.sin(x * .005 * 2.7 + 3.4 * 1.3 + t * .013) * 26 * .35; };
      var sil = rgb(mix([60, 35, 25], [15, 10, 20], night));
      for (var c = 0; c < 4; c++) {
        var cx = ((t * .008 + c * .07) % 1.4 - .2) * w, cyy = ry(cx), sc = Math.min(w, h) / 500, st2 = Math.sin(t * 2.2 + c);
        g.fillStyle = sil; g.strokeStyle = sil; g.lineCap = 'round';
        g.beginPath(); g.ellipse(cx, cyy - 22 * sc, 18 * sc, 8 * sc, 0, 0, TAU); g.fill(); g.beginPath(); g.ellipse(cx - 2 * sc, cyy - 30 * sc, 8 * sc, 6 * sc, 0, 0, TAU); g.fill();
        g.lineWidth = 4 * sc; g.beginPath(); g.moveTo(cx + 14 * sc, cyy - 24 * sc); g.quadraticCurveTo(cx + 26 * sc, cyy - 28 * sc, cx + 26 * sc, cyy - 38 * sc); g.stroke();
        g.beginPath(); g.ellipse(cx + 29 * sc, cyy - 39 * sc, 5 * sc, 3 * sc, 0, 0, TAU); g.fill();
        if (c % 2 === 0) { g.fillRect(cx - 5 * sc, cyy - 46 * sc, 6 * sc, 12 * sc); g.beginPath(); g.arc(cx - 2 * sc, cyy - 49 * sc, 3.5 * sc, 0, TAU); g.fill(); }
        g.lineWidth = 2.4 * sc; [[-12, 1], [-6, -1], [8, -1], [13, 1]].forEach(function (l) { g.beginPath(); g.moveTo(cx + l[0] * sc, cyy - 16 * sc); g.lineTo(cx + l[0] * sc + st2 * l[1] * 5 * sc, cyy); g.stroke(); });
      }
      g.strokeStyle = rgb(mix([255, 220, 170], [200, 190, 220], night), .35); g.lineWidth = 1; g.beginPath();
      sand.forEach(function (q) { var x = ((q.x + t * .06 * q.v) % 1.2 - .1) * w, y = q.y * h + Math.sin(t * 2 + q.x * 30) * 3; g.moveTo(x, y); g.lineTo(x + q.l, y - q.l * .1); }); g.stroke();
    };
  };

  // Champagne: rising bubbles, gold bokeh and glitter
  SCN.champagne = function (s, P) {
    var R = rng(141), bub = [], bok = [], gl = [];
    for (var i = 0; i < 90; i++) bub.push({x: R(), o: R(), sp: .05 + R() * .08, r: 1 + R() * 3.5, ph: R() * TAU, st: R() < .6 ? (R() * 6 | 0) : -1});
    for (var j = 0; j < 22; j++) bok.push({x: R(), y: R(), r: 30 + R() * 70, ph: R() * TAU, z: R()});
    for (var k = 0; k < 60; k++) gl.push({x: R(), y: R(), ph: R() * TAU});
    return function (g, w, h, t, p) {
      var gr = g.createRadialGradient(w * .5, h * .4, 0, w * .5, h * .5, Math.max(w, h) * .8); gr.addColorStop(0, rgb(mix(P.bg, P.accent, .22))); gr.addColorStop(1, rgb(mix(P.bg, [0, 0, 0], .4))); g.fillStyle = gr; g.fillRect(0, 0, w, h);
      bok.forEach(function (b) { var x = (b.x + Math.sin(t * .05 + b.ph) * .05) * w, y = ((b.y - p * .3 * b.z) % 1 + 1) % 1 * h; glowDot(g, x, y, b.r, mix(P.accent, [255, 240, 200], .4), .16 + .1 * Math.sin(t * .6 + b.ph)); });
      var speed = 1 + p * 1.5;
      bub.forEach(function (b) { var life = ((b.o + t * b.sp * speed) % 1), x = (b.st >= 0 ? (.12 + b.st * .15) : b.x) * w + Math.sin(t * 3 + b.ph + life * 9) * 4, y = h * (1.05 - life * 1.15), r = b.r * (.6 + life * .8);
        g.strokeStyle = 'rgba(255,240,200,' + (.6 - life * .3) + ')'; g.lineWidth = .8; g.beginPath(); g.arc(x, y, r, 0, TAU); g.stroke(); g.fillStyle = 'rgba(255,255,255,.7)'; g.beginPath(); g.arc(x - r * .35, y - r * .35, r * .25, 0, TAU); g.fill(); });
      gl.forEach(function (q) { var a = Math.max(0, Math.sin(t * 2.5 + q.ph * 3)); if (a < .2) return; var x = q.x * w, y = q.y * h, z = 3 * a; g.fillStyle = rgb(mix(P.accent, [255, 255, 255], .5), a); g.beginPath(); g.moveTo(x, y - z * 2); g.lineTo(x + z * .4, y); g.lineTo(x, y + z * 2); g.lineTo(x - z * .4, y); g.fill(); g.beginPath(); g.moveTo(x - z * 2, y); g.lineTo(x, y + z * .4); g.lineTo(x + z * 2, y); g.lineTo(x, y - z * .4); g.fill(); });
    };
  };

  // Papillons: a cloud of butterflies that gathers, circles, then draws a heart
  SCN.butterflies = function (s, P) {
    var R = rng(151), N = 48, B = [], fl = [];
    var cs = [P.accent, mix(P.accent, [255, 255, 255], .4), mix(P.accent, P.deep, .3), [250, 190, 80], mix(P.soft, P.accent, .5)];
    for (var i = 0; i < N; i++) B.push({x: R() * s.w, y: R() * s.h, vx: 0, vy: 0, c: cs[i % 5], s: 9 + R() * 7, ph: R() * TAU, wx: R(), wy: R()});
    for (var f = 0; f < 9; f++) fl.push({x: (f + .5) / 9, h: .06 + R() * .07, ph: R() * TAU, r: 10 + R() * 8});
    return function (g, w, h, t, p) {
      skyGrad(g, w, h, [[0, mix(P.bg, [255, 255, 255], .3)], [1, mix(P.soft, P.bg, .2)]]);
      for (var b = 0; b < 10; b++) glowDot(g, w * ((b * .29 + .1) % 1), h * ((b * .37 + .2) % 1), 60 + b * 6, mix(P.accent, [255, 255, 255], .6), .12);
      fl.forEach(function (q) { var x = q.x * w + Math.sin(t + q.ph) * 4, y = h * (1 - q.h); g.strokeStyle = 'rgb(90,130,80)'; g.lineWidth = 2; g.beginPath(); g.moveTo(q.x * w, h); g.quadraticCurveTo(q.x * w, h - q.h * h * .5, x, y); g.stroke(); petal5(g, x, y, q.r, 1, rgb(mix(P.accent, [255, 255, 255], .3)), 'rgb(250,210,90)', t * .2 + q.ph); });
      var cx = w / 2, cy = h * .45, ring = sstep(.18, .45, p), heart = sstep(.55, .85, p), sc = Math.min(w, h) / 40;
      B.forEach(function (b, i) {
        var u = i / N * TAU, wxp = (b.wx + Math.sin(t * .07 + i) * .3) % 1, tx = w * (.1 + .8 * Math.abs(wxp)), ty = h * (.15 + .6 * Math.abs((b.wy + Math.cos(t * .05 + i) * .3) % 1));
        var rx = cx + Math.cos(u + t * .3) * Math.min(w, h) * .34, ryy = cy + Math.sin(u + t * .3) * Math.min(w, h) * .34;
        var hx = cx + 16 * Math.pow(Math.sin(u), 3) * sc, hy = cy - (13 * Math.cos(u) - 5 * Math.cos(2 * u) - 2 * Math.cos(3 * u) - Math.cos(4 * u)) * sc;
        var gx = tx + (rx - tx) * ring, gy = ty + (ryy - ty) * ring; gx += (hx - gx) * heart; gy += (hy - gy) * heart;
        b.vx += (gx - b.x) * .004 + Math.sin(t * 2 + b.ph) * .15; b.vy += (gy - b.y) * .004 + Math.cos(t * 1.7 + b.ph) * .15; b.vx *= .92; b.vy *= .92; b.x += b.vx; b.y += b.vy;
        var fl2 = .2 + .8 * Math.abs(Math.sin(t * 11 + b.ph)), ang = Math.atan2(b.vy, b.vx) + Math.PI / 2;
        g.save(); g.translate(b.x, b.y); g.rotate(ang * .3); g.fillStyle = rgb(b.c, .92);
        g.strokeStyle = rgb(mix(b.c, P.black, .55)); g.lineWidth = 1.2;
        [-1, 1].forEach(function (sd) { g.save(); g.scale(sd * fl2, 1); g.beginPath(); g.ellipse(b.s * .7, -b.s * .4, b.s * .75, b.s * .55, .5, 0, TAU); g.fill(); g.stroke(); g.beginPath(); g.ellipse(b.s * .55, b.s * .45, b.s * .5, b.s * .38, -.4, 0, TAU); g.fill(); g.stroke(); g.fillStyle = 'rgba(255,255,255,.7)'; g.beginPath(); g.arc(b.s * .95, -b.s * .55, b.s * .12, 0, TAU); g.fill(); g.fillStyle = rgb(b.c, .92); g.restore(); });
        g.fillStyle = rgb(P.deep); g.fillRect(-1, -b.s * .7, 2, b.s * 1.4); g.strokeStyle = rgb(P.deep); g.lineWidth = .8; g.beginPath(); g.moveTo(0, -b.s * .7); g.lineTo(-b.s * .3, -b.s * 1.1); g.moveTo(0, -b.s * .7); g.lineTo(b.s * .3, -b.s * 1.1); g.stroke(); g.restore();
      });
    };
  };

  // Hiver: a snow globe; scrolling shakes it, then the snow settles
  SCN.globe = function (s, P) {
    var R = rng(161), fl = [], trees = [], houses = [], last = null, swirl = 0;
    for (var i = 0; i < 160; i++) fl.push({x: R(), y: R(), r: .8 + R() * 2.2, vx: 0, vy: 0, ph: R() * TAU});
    for (var j = 0; j < 9; j++) trees.push({x: .08 + R() * .84, s: .5 + R() * .7, y: .72 + R() * .12});
    trees.sort(function (a, b) { return a.y - b.y; });
    for (var k = 0; k < 3; k++) houses.push({x: .25 + k * .22 + (R() - .5) * .05, s: .8 + R() * .4});
    return function (g, w, h, t, p) {
      var sy = scrollY; if (last == null) last = sy; var v = sy - last; last = sy; swirl = Math.min(6, swirl * .96 + Math.abs(v) * .03);
      g.clearRect(0, 0, w, h); g.save(); g.beginPath(); g.arc(w / 2, h / 2, Math.min(w, h) / 2, 0, TAU); g.clip();
      skyGrad(g, w, h, [[0, mix(P.deep, [20, 30, 70], .5)], [.7, mix(P.deep, [80, 100, 150], .5)], [1, [220, 230, 245]]]);
      var m = moonImage(), mr = w * .06; g.drawImage(m, w * .7 - mr, h * .2 - mr, mr * 2, mr * 2);
      g.fillStyle = 'rgb(235,240,250)'; g.beginPath(); g.moveTo(0, h); g.lineTo(0, h * .78); g.quadraticCurveTo(w * .5, h * .7, w, h * .8); g.lineTo(w, h); g.fill();
      houses.forEach(function (hs) { var x = hs.x * w, y = h * .79, hw = w * .07 * hs.s, hh = hw * .8; g.fillStyle = rgb(mix(P.accent, [120, 60, 40], .5)); g.fillRect(x - hw / 2, y - hh, hw, hh); g.fillStyle = '#f4f6fb'; g.beginPath(); g.moveTo(x - hw * .65, y - hh); g.lineTo(x, y - hh * 1.8); g.lineTo(x + hw * .65, y - hh); g.fill(); var fl3 = .8 + .2 * Math.sin(t * 6 + hs.x * 10); glowDot(g, x, y - hh * .5, hw, [255, 200, 110], .5 * fl3); g.fillStyle = 'rgba(255,210,120,' + fl3 + ')'; g.fillRect(x - hw * .18, y - hh * .7, hw * .36, hw * .3); for (var sm = 0; sm < 5; sm++) { var a = ((t * .25 + sm * .2) % 1); g.fillStyle = 'rgba(230,235,245,' + (.35 * (1 - a)) + ')'; g.beginPath(); g.arc(x + hw * .25 + Math.sin(t + sm) * 4 * a, y - hh * 1.5 - a * hh * 1.6, 3 + a * 6, 0, TAU); g.fill(); } });
      trees.forEach(function (tr) { var x = tr.x * w, y = tr.y * h, th = h * .18 * tr.s; for (var q = 0; q < 4; q++) { var yy = y - th * (q * .22), tw = th * (.42 - q * .08); g.fillStyle = 'rgb(30,70,55)'; g.beginPath(); g.moveTo(x - tw, yy); g.lineTo(x, yy - th * .38); g.lineTo(x + tw, yy); g.fill(); g.fillStyle = '#f2f5fb'; g.beginPath(); g.moveTo(x - tw * .45, yy - th * .2); g.lineTo(x, yy - th * .38); g.lineTo(x + tw * .45, yy - th * .2); g.fill(); } });
      var cxg = w / 2, cyg = h / 2;
      fl.forEach(function (f) { var px = f.x * w, py = f.y * h, dx = px - cxg, dy = py - cyg; f.vx += (-dy * .0006 * swirl) + Math.sin(t + f.ph) * .02; f.vy += (dx * .0006 * swirl) + .015 + (swirl > 1 ? -.01 : 0); f.vx *= .95; f.vy *= .95; f.x += f.vx / w * 3; f.y += f.vy / h * 3; if (f.y > .98) { f.y = .02 + Math.random() * .1; f.x = Math.random(); } if (f.x < 0) f.x += 1; if (f.x > 1) f.x -= 1; if (f.y < 0) f.y += .9; g.fillStyle = 'rgba(255,255,255,.9)'; g.beginPath(); g.arc(f.x * w, f.y * h, f.r, 0, TAU); g.fill(); });
      g.restore();
      g.strokeStyle = 'rgba(255,255,255,.35)'; g.lineWidth = 6; g.beginPath(); g.arc(w / 2, h / 2, Math.min(w, h) / 2 - 12, 3.6, 4.6); g.stroke();
    };
  };
  SCN.snowfall = function (s, P) {
    var R = rng(171), fl = []; for (var i = 0; i < 70; i++) fl.push({x: R(), y: R(), r: .8 + R() * 2.4, v: .02 + R() * .04, ph: R() * TAU});
    return function (g, w, h, t, p) { g.clearRect(0, 0, w, h); fl.forEach(function (f) { var y = ((f.y + t * f.v + p * .3) % 1), x = f.x + Math.sin(t * .7 + f.ph) * .02; g.fillStyle = rgb(mix(P.accent, [255, 255, 255], .6), .8); g.beginPath(); g.arc(x * w, y * h, f.r, 0, TAU); g.fill(); }); };
  };

  // Feux d'artifice: a city at night, fireworks more and more often as you scroll
  SCN.fireworks = function (s, P) {
    var R = rng(181), bld = [], parts = [], rockets = [], next = 0, st = [];
    var x = 0; while (x < s.w) { var bw = 18 + R() * 40; bld.push({x: x, w: bw, h: .06 + R() * .16, win: R(), dome: R() < .12}); x += bw + 2; }
    for (var j = 0; j < 120; j++) st.push({x: R(), y: R() * .6, ph: R() * TAU});
    var cols = [P.accent, [255, 230, 150], [255, 255, 255], [240, 90, 90], mix(P.soft, [255, 255, 255], .4), [120, 200, 255]];
    return function (g, w, h, t, p) {
      g.globalCompositeOperation = 'source-over';
      var gr = g.createLinearGradient(0, 0, 0, h); gr.addColorStop(0, rgb(mix(P.bg, [5, 5, 20], .5), .4)); gr.addColorStop(1, rgb(mix(P.bg, [40, 20, 50], .5), .4)); g.fillStyle = gr; g.fillRect(0, 0, w, h);
      st.forEach(function (q) { g.fillStyle = 'rgba(255,255,255,' + (.2 + .5 * Math.abs(Math.sin(t + q.ph))) * .5 + ')'; g.fillRect(q.x * w, q.y * h, 1.3, 1.3); });
      var every = 1.1 - clamp(p) * .8;
      if (t > next) { next = t + every * (.6 + Math.random() * .8); rockets.push({x: w * (.15 + Math.random() * .7), y: h * .86, vy: -(h * .011 + Math.random() * h * .004), ty: h * (.15 + Math.random() * .3), c: cols[(Math.random() * cols.length) | 0]}); }
      g.globalCompositeOperation = 'lighter';
      rockets = rockets.filter(function (r) { r.y += r.vy; r.vy *= .985; glowDot(g, r.x, r.y, 8, [255, 220, 170], .8); if (r.y <= r.ty) { var n = 70 + (p * 60 | 0), big = 1 + p; for (var i = 0; i < n; i++) { var a = Math.random() * TAU, sp = (1.5 + Math.random() * 3.5) * big * Math.min(w, h) / 380; parts.push({x: r.x, y: r.y, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp, l: 1, c: Math.random() < .2 ? [255, 255, 255] : r.c}); } return false; } return true; });
      parts = parts.filter(function (q) { q.x += q.vx; q.y += q.vy; q.vy += .03; q.vx *= .985; q.vy *= .985; q.l -= .012; if (q.l <= 0) return false; glowDot(g, q.x, q.y, 7, q.c, q.l * .5); g.fillStyle = rgb(q.c, q.l); g.fillRect(q.x - 1.5, q.y - 1.5, 3, 3); return true; });
      g.globalCompositeOperation = 'source-over';
      var sil = rgb(mix(P.bg, [0, 0, 0], .6)), gy = h * .9;
      bld.forEach(function (b) { var bh = h * b.h; g.fillStyle = sil; g.fillRect(b.x, gy - bh, b.w, bh + h); if (b.dome) { g.beginPath(); g.arc(b.x + b.w / 2, gy - bh, b.w / 2, Math.PI, 0); g.fill(); g.fillRect(b.x + b.w - 4, gy - bh - b.w * .9, 4, b.w * .9); } for (var wy = gy - bh + 6; wy < gy - 4; wy += 9) for (var wx = b.x + 4; wx < b.x + b.w - 4; wx += 8) if (((wx * 7 + wy * 3) % 11) < 4 * b.win) { g.fillStyle = 'rgba(255,210,130,' + (.5 + .4 * Math.sin(t * .5 + wx)) + ')'; g.fillRect(wx, wy, 3, 4); } });
      g.fillStyle = sil; g.fillRect(0, gy, w, h);
    };
  };

  // Aurore: northern lights over mountains and a still lake
  SCN.aurora = function (s, P) {
    var R = rng(191), st = []; for (var i = 0; i < 200; i++) st.push({x: R(), y: R() * .6, z: R(), ph: R() * TAU});
    var cols = [[80, 255, 170], [60, 200, 255], mix(P.accent, [255, 120, 220], .5)];
    function ribbons(g, w, h, t, p, flip, hz, alpha) {
      g.globalCompositeOperation = 'lighter';
      for (var r = 0; r < 3; r++) {
        var c = cols[r], k = .5 + .5 * clamp(p * 1.4);
        for (var x = 0; x < w; x += 5) {
          var y = h * (.18 + r * .07) + Math.sin(x * .006 + t * .25 + r * 2) * h * .06 + Math.sin(x * .017 - t * .4 + r) * h * .02;
          var len = h * .3 * (.5 + .5 * Math.sin(x * .011 + t * .5 + r * 1.7)) * k;
          var y0 = flip ? 2 * hz - y : y, y1 = flip ? 2 * hz - (y + len) : y + len;
          var gr = g.createLinearGradient(0, y0, 0, y1); gr.addColorStop(0, rgb(c, .5 * alpha * k)); gr.addColorStop(1, rgb(c, 0));
          g.fillStyle = gr; g.fillRect(x, Math.min(y0, y1), 5, Math.abs(y1 - y0));
        }
      }
      g.globalCompositeOperation = 'source-over';
    }
    return function (g, w, h, t, p) {
      var hz = h * .7;
      skyGrad(g, w, h, [[0, mix(P.bg, [4, 8, 22], .5)], [.7, mix(P.bg, [12, 30, 50], .5)], [1, mix(P.bg, [4, 8, 20], .6)]]);
      st.forEach(function (q) { g.globalAlpha = .3 + .7 * Math.abs(Math.sin(t * (.4 + q.z) + q.ph)); g.fillStyle = '#fff'; g.fillRect(q.x * w, q.y * h, q.z * 1.4 + .4, q.z * 1.4 + .4); }); g.globalAlpha = 1;
      ribbons(g, w, h, t, p, false, hz, 1);
      g.fillStyle = 'rgb(10,16,26)'; g.beginPath(); g.moveTo(0, hz); for (var x = 0; x <= w; x += 6) g.lineTo(x, hz - Math.abs(Math.sin(x * .011 + 1)) * h * .12 - Math.abs(Math.sin(x * .031)) * h * .04); g.lineTo(w, hz); g.fill();
      g.save(); g.beginPath(); g.rect(0, hz, w, h - hz); g.clip(); g.fillStyle = 'rgb(6,12,22)'; g.fillRect(0, hz, w, h); ribbons(g, w, h, t, p, true, hz, .45);
      g.strokeStyle = 'rgba(200,230,255,.08)'; g.lineWidth = 1; for (var ry = hz + 6; ry < h; ry += 7) { g.beginPath(); g.moveTo(0, ry + Math.sin(t + ry) * 1.5); g.lineTo(w, ry + Math.sin(t * 1.3 + ry) * 1.5); g.stroke(); }
      g.restore();
    };
  };


  // ================= Premium: scenes painted by the graphics chip =================
  // Every Premium scene is a fragment shader: the phone's GPU paints each pixel from a few formulas
  // (sky, sun, water, dunes, mist, velvet, frost…). It costs a fraction of a video, scales to any
  // screen, and the scroll (uP) and the clock (uT) drive the light. The page draws at a reduced
  // resolution that adapts to the phone: it drops when frames get slow and climbs back when they are
  // quick. A 2D canvas on top adds what shaders do badly: flowers, butterflies, lanterns, fireworks.
  var LXGL = null;
  var LX_PRE = [
    '#ifdef GL_FRAGMENT_PRECISION_HIGH', 'precision highp float;', '#else', 'precision mediump float;', '#endif',
    'varying vec2 v;uniform vec2 uR;uniform float uT,uP,uV;uniform vec3 uA,uD,uB;',
    'float hash(vec2 p){p=fract(p*vec2(123.34,456.21));p+=dot(p,p+45.32);return fract(p.x*p.y);}',
    'float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1.,0.)),f.x),mix(hash(i+vec2(0.,1.)),hash(i+vec2(1.,1.)),f.x),f.y);}',
    'float fbm(vec2 p){float s=0.,a=.5;for(int i=0;i<5;i++){s+=a*noise(p);p=p*2.02+vec2(1.7,9.2);a*=.5;}return s;}',
    'float fbm3(vec2 p){float s=0.,a=.5;for(int i=0;i<3;i++){s+=a*noise(p);p=p*2.02+vec2(1.7,9.2);a*=.5;}return s;}',
    'mat2 rot(float a){float c=cos(a),s=sin(a);return mat2(c,-s,s,c);}',
    'float vig(vec2 u){return 1.-.5*pow(length(u-.5)*1.25,2.4);}',
    'vec3 finish(vec3 c,vec2 u){c*=vig(u);c+=(hash(u*uR+fract(uT*.7)*31.)-.5)*.04;return c;}',
    'float stars(vec2 u,float ar,float dens){vec2 p=u*vec2(ar,1.)*dens;vec2 i=floor(p),f=fract(p);float h=hash(i);vec2 c=vec2(.2+.6*hash(i+.1),.2+.6*hash(i+.2));float d=length(f-c);float s=smoothstep(.07,0.,d)*step(.78,h);return s*(.45+.55*sin(uT*(1.+h*3.)+h*20.));}',
    'float disc(vec2 q,vec2 p,float r){float d=length(q-p);return smoothstep(r,r-.012,d);}',
    'float ring(vec2 q,vec2 p,float r){float d=length(q-p);return smoothstep(r-.02,r,d)*smoothstep(r,r-.01,d);}'
  ].join('\n');
  var LX_MAIN = '\nvoid main(){float ar=uR.x/uR.y;vec3 c=scene(v,ar);gl_FragColor=vec4(finish(c,v),1.);}';
  var LXSH = {};

  // Savane d'or: a golden afternoon that turns to dusk; sun, rays, haze, acacias.
  LXSH.savane = [
    'vec3 scene(vec2 u,float ar){',
    ' float day=1.-smoothstep(.05,.9,uP);float hz=.36;vec2 q=vec2((u.x-.5)*ar,u.y);',
    ' vec2 sun=vec2(.38*ar,hz+.44*day+.06);',
    ' vec3 top=mix(vec3(.10,.09,.24),vec3(.33,.58,.84),day),mid=mix(vec3(.92,.40,.18),vec3(.99,.84,.55),day);',
    ' vec3 sky=mix(mid,top,smoothstep(hz,1.,u.y+(1.-day)*.1));',
    ' float haze=fbm3(vec2(u.x*2.5+uT*.03,u.y*5.));sky=mix(sky,mid*1.05,(1.-smoothstep(hz,hz+.3,u.y))*haze*.7);',
    ' float d=length(q-sun);vec3 sc=mix(vec3(1.,.45,.15),vec3(1.,.93,.7),day);',
    ' sky+=sc*(.3*exp(-d*9.)+.12*exp(-d*2.2)+.02/(d*12.+.3));sky=mix(sky,vec3(1.,.97,.85),smoothstep(.04,.03,d)*.9);',
    ' vec2 dirv=normalize(q-sun+.0001);float ray=pow(noise(dirv*3.+uT*.05),2.)*pow(noise(dirv*7.-uT*.03+2.),1.5);',
    ' sky+=sc*ray*.22*smoothstep(0.,.4,d)*exp(-d*1.6)*day*step(hz-.02,u.y);',
    ' float dep=clamp((hz-u.y)/hz,0.,1.);vec2 gp=vec2((u.x-.5)*ar/(.06+dep*1.4),1./(.06+dep*1.4));',
    ' float gn=fbm(gp*vec2(2.2,.9)+vec2(uT*.25+uV*2.,0.));',
    ' vec3 gcol=mix(vec3(.72,.52,.22),vec3(.98,.82,.42),gn)*mix(.28,1.,day);gcol=mix(gcol,mid*.7*mix(.4,1.,day),pow(1.-dep,3.)*.75);',
    ' vec3 c=u.y>hz?sky:gcol;return c;}'
  ].join('\n');

  // Étang de lotus: water from above, ripples, caustics, lily pads, light.
  LXSH.lotus = [
    'vec3 scene(vec2 u,float ar){',
    ' vec2 q=vec2((u.x-.5)*ar,u.y-.5);float t=uT;vec2 p=q*5.;float h=0.;vec2 g=vec2(0.);',
    ' for(int i=0;i<5;i++){float fi=float(i);vec2 k=vec2(cos(fi*1.9+.7),sin(fi*1.9+.7))*(1.4+fi*.9);float ph=dot(k,p)-t*(.6+fi*.25);float a=.06/(1.+fi*.6);h+=a*sin(ph);g+=a*cos(ph)*k;}',
    ' for(int i=0;i<3;i++){float fi=float(i);float cyc=floor(t/3.5+fi*.33);vec2 c0=vec2(hash(vec2(cyc,fi))-.5,hash(vec2(fi,cyc))-.5)*vec2(ar,1.)*.85;float age=fract(t/3.5+fi*.33)*3.5;float r=length(q-c0);float w=sin(r*70.-age*7.)*exp(-age*1.1)*exp(-r*4.)*smoothstep(age*.3+.08,age*.3,r)*.5;h+=w*.03;g+=normalize(q-c0+.0001)*w*2.;}',
    ' vec3 n=normalize(vec3(-g.x,-g.y,1.));',
    ' vec3 deep=mix(uD*.6,vec3(.02,.12,.12),.5),shal=mix(uA,vec3(.1,.45,.42),.6);float dv=fbm3(q*1.5+t*.02);vec3 wat=mix(deep,shal,dv*.8);',
    ' float ca=pow(1.-abs(sin((h*18.+fbm3(p*.6+t*.1)*4.)*3.14)),6.);wat+=vec3(.5,.9,.8)*ca*.25*dv;',
    ' vec3 skyc=mix(vec3(.75,.88,.86),vec3(.98,.95,.85),u.y);float fr=pow(1.-abs(n.z),2.)*.5+.08;vec3 c=mix(wat,skyc,fr);',
    ' vec3 ld=normalize(vec3(.3,.8,.6));float sp=pow(max(dot(reflect(vec3(0.,0.,-1.),n),ld),0.),90.);c+=vec3(1.,.97,.9)*sp*.9;',
    ' for(int i=0;i<7;i++){float fi=float(i);vec2 c0=vec2(hash(vec2(fi,2.))-.5,hash(vec2(3.,fi))-.5)*vec2(ar,1.)*.95;float rr=.07+hash(vec2(fi,9.))*.06;',
    '  vec2 pp=rot(fi)*(q-c0-vec2(sin(t*.2+fi)*.004,0.));float ang=atan(pp.y,pp.x);float dd=length(pp*vec2(1.,1.15))-rr+smoothstep(.3,0.,abs(ang))*rr*.8;',
    '  c=mix(c,c*.55,smoothstep(.0,-.03,dd+.035)*(1.-smoothstep(.004,-.004,dd)));',
    '  vec3 pc=mix(vec3(.10,.33,.12),vec3(.36,.62,.26),fbm3(pp*30.+fi))*(1.-pow(1.-abs(sin(ang*8.)),30.)*.25);',
    '  pc+=vec3(.6,.8,.5)*pow(max(0.,1.-length(pp-vec2(-.02,.03))*9.),3.)*.5;',
    '  c=mix(c,pc,smoothstep(.004,-.004,dd));}',
    ' return c;}'
  ].join('\n');

  // Forêt: trunks in layers of mist, warm light shafts, moss.
  LXSH.foret = [
    'vec3 scene(vec2 u,float ar){',
    ' vec3 fog=vec3(.78,.84,.74),warm=vec3(1.,.86,.52);vec3 c=mix(vec3(.36,.44,.32),mix(fog,vec3(1.,.96,.82),.6),smoothstep(.1,.9,u.y));',
    ' float holes=fbm(vec2(u.x*ar*2.6+.4,u.y*2.2));',
    ' for(int k=0;k<4;k++){float fk=float(k);float z=1.-fk/4.;float sc=3.6-fk*.8;float off=fk*7.3+uP*(.2+fk*.3);float x=u.x*sc+off;float id=floor(x);float n1=hash(vec2(id,fk));float n2=hash(vec2(id*3.1,fk+9.));',
    '  if(n2>.38){float cx=fract(x)-.5-(n1-.5)*.36;float wd=(.06+n1*.08)*(1.+(1.-u.y)*.9);cx+=sin(u.y*3.5+n1*9.)*.025*(1.-u.y);',
    '   float tr=smoothstep(wd+.02,wd,abs(cx));float bark=fbm3(vec2(cx*26.+id,u.y*22.+fk))*.5;float side=smoothstep(-wd,wd*.6,cx)*.6+.2;',
    '   vec3 tc=mix(vec3(.05,.06,.04),vec3(.3,.25,.18),bark)*side*(.4+.6*(1.-z));tc=mix(tc,fog,z*z*.8);c=mix(c,tc,tr);}',
    '  if(k==1){vec2 rp=vec2(u.x+(1.-u.y)*.62,0.);float shaft=pow(noise(vec2(rp.x*5.+uT*.03,2.)),2.)*pow(noise(vec2(rp.x*15.-uT*.02,5.)),1.2);',
    '   float sm=smoothstep(.05,.8,u.y)*smoothstep(.0,.7,1.-abs(u.x-.58)*1.1)*(.4+.6*smoothstep(.3,.7,holes));c+=warm*shaft*sm*2.2;}}',
    ' float can=smoothstep(.7,1.,u.y+holes*.35);c=mix(c,vec3(.06,.10,.05),can*.85);c+=warm*.35*smoothstep(.55,1.,u.y)*smoothstep(.55,.8,holes);',
    ' float gr=smoothstep(.22,.0,u.y);vec3 moss=mix(vec3(.09,.15,.06),vec3(.32,.40,.15),fbm3(vec2(u.x*ar*8.,u.y*30.)));c=mix(c,moss,gr*.95);',
    ' float wisp=fbm3(vec2(u.x*ar*2.-uT*.04,u.y*4.))*smoothstep(.45,.0,u.y);c=mix(c,fog,wisp*.4);',
    ' float night=smoothstep(.6,1.,uP);c=mix(c,c*vec3(.3,.42,.6),night*.65);return c;}'
  ].join('\n');

  // Cerisiers: a soft spring sky with bokeh.
  LXSH.cerisiers = [
    'vec3 scene(vec2 u,float ar){',
    ' vec2 q=vec2((u.x-.5)*ar,u.y);vec3 c=mix(vec3(.93,.80,.82),vec3(.80,.86,.95),u.y);',
    ' c=mix(c,vec3(1.,.95,.9),smoothstep(.6,0.,length(q-vec2(.3*ar,.85)))*.6);',
    ' for(int i=0;i<18;i++){float fi=float(i);float sp=.02+hash(vec2(fi,1.))*.03;vec2 p=vec2(hash(vec2(fi,2.))*1.2-.1,fract(hash(vec2(fi,3.))+uT*sp*.3+uP*.25*hash(vec2(fi,4.))))*vec2(ar,1.)-vec2(ar*.5,0.);',
    '  float r=.03+hash(vec2(fi,5.))*.08;vec3 bc=mix(vec3(1.,.75,.82),vec3(1.,.95,.9),hash(vec2(fi,6.)));c+=bc*(disc(q,p,r)*.10+ring(q,p,r)*.14)*(.6+.4*sin(uT*.8+fi));}',
    ' return c;}'
  ].join('\n');

  // Champ d'or: the sun crosses the sky over a sunflower field; lit clouds.
  LXSH.tournesols = [
    'vec3 scene(vec2 u,float ar){',
    ' float hz=.48;vec2 q=vec2((u.x-.5)*ar,u.y);float a=3.14159*(.15+.7*clamp(uP*1.1,0.,1.));vec2 sun=vec2(-.46*ar*cos(a),hz+.5*sin(a));',
    ' float late=abs(uP-.5)*2.;vec3 top=mix(vec3(.30,.56,.90),vec3(.55,.45,.75),late*.6),low=mix(vec3(.80,.90,.98),vec3(.98,.78,.60),late*.8);',
    ' vec3 sky=mix(low,top,smoothstep(hz,1.,u.y));',
    ' vec2 cp=vec2(u.x*ar*1.6+uT*.015,u.y*3.);float cl=fbm(cp);float cl2=fbm(cp+normalize(sun-q+.0001)*.05);',
    ' float cm=smoothstep(.48,.72,cl)*smoothstep(hz,hz+.25,u.y);vec3 cc=mix(vec3(.75,.78,.85),vec3(1.,.99,.95),smoothstep(-.05,.1,cl2-cl)+.3);cc=mix(cc,vec3(1.,.85,.7),late*.4);sky=mix(sky,cc,cm*.9);',
    ' float d=length(q-sun);sky+=vec3(1.,.95,.8)*(.6*exp(-d*6.)+.2*exp(-d*1.5));sky=mix(sky,vec3(1.,1.,.95),smoothstep(.07,.05,d));',
    ' float dep=clamp((hz-u.y)/hz,0.,1.);float pz=.05+dep*1.6;vec2 gp=vec2((u.x-.5)*ar/pz,1./pz);',
    ' float heads=smoothstep(.55,.9,noise(gp*vec2(7.,3.5)+vec2(0.,uT*.05)));float heads2=smoothstep(.6,.95,noise(gp*vec2(13.,7.)+3.));',
    ' vec3 green=mix(vec3(.25,.42,.12),vec3(.45,.6,.2),fbm3(gp*vec2(3.,2.)));vec3 yel=mix(vec3(.95,.72,.1),vec3(1.,.9,.3),heads2);',
    ' vec3 fld=mix(green,yel,max(heads,heads2*.6));fld*=mix(.6,1.,dep)*mix(.55,1.,1.-late*.5);fld=mix(fld,low*.8,pow(1.-dep,4.)*.6);',
    ' vec3 c=u.y>hz?sky:fld;c=mix(c,c*vec3(1.05,1.,.9),late*.5);return c;}'
  ].join('\n');

  // Nuit des lanternes: a night sky over still water, warm from the lanterns.
  LXSH.lanternes = [
    'vec3 scene(vec2 u,float ar){',
    ' float wl=.3;vec2 q=vec2((u.x-.5)*ar,u.y);vec3 c=mix(vec3(.08,.05,.14),vec3(.01,.02,.08),smoothstep(wl,1.,u.y));',
    ' c+=vec3(.9,.45,.15)*.35*exp(-(u.y-wl)*5.)*step(wl,u.y);c+=vec3(1.,1.,.95)*stars(u,ar,70.)*step(wl,u.y)*.9;',
    ' float cl=fbm3(vec2(u.x*ar*2.+uT*.02,u.y*6.));c=mix(c,vec3(.25,.15,.25),smoothstep(.55,.8,cl)*.35*step(wl,u.y));',
    ' float m=.12*noise(vec2(u.x*ar*3.,1.))+.05*noise(vec2(u.x*ar*9.,2.));c=mix(c,vec3(.03,.02,.06),step(u.y,wl+m)*step(wl,u.y));',
    ' if(u.y<wl){float dep=(wl-u.y)/wl;float pz=.08+dep*1.5;vec2 wp=vec2((u.x-.5)*ar/pz,1./pz);float h=0.;vec2 g=vec2(0.);',
    '  for(int i=0;i<4;i++){float fi=float(i);vec2 k=vec2(cos(fi*2.1),sin(fi*2.1))*(2.+fi*1.5);float ph=dot(k,wp*.6)-uT*(.8+fi*.3);float a=.5/(1.+fi);h+=a*sin(ph);g+=a*cos(ph)*k;}',
    '  vec2 ru=vec2(u.x+g.x*.004,2.*wl-u.y+g.y*.01);vec3 rc=mix(vec3(.08,.05,.14),vec3(.01,.02,.08),smoothstep(wl,1.,ru.y));',
    '  rc+=vec3(.95,.5,.2)*.5*exp(-(ru.y-wl)*4.);rc+=vec3(1.)*stars(ru,ar,70.)*.4;',
    '  float m2=.12*noise(vec2(ru.x*ar*3.,1.))+.05*noise(vec2(ru.x*ar*9.,2.));rc=mix(rc,vec3(.03,.02,.06),step(ru.y,wl+m2));',
    '  float glit=pow(max(0.,.5+.5*g.y),8.)*.15;c=mix(rc*.75,vec3(.05,.03,.05),.25)+vec3(1.,.7,.4)*glit*dep;}',
    ' return c;}'
  ].join('\n');

  // Roseraie: velvet with folds and sheen, gold bokeh.
  LXSH.roseraie = [
    'vec3 scene(vec2 u,float ar){',
    ' vec2 q=vec2((u.x-.5)*ar,u.y);vec3 base=mix(uD,vec3(.25,.02,.06),.5);',
    ' float folds=fbm(vec2(u.x*ar*2.2+uT*.01,u.y*1.3))*2.-1.;float sheen=pow(1.-abs(sin(folds*3.3+u.y*2.)),4.);',
    ' vec3 c=base*(.5+.6*fbm3(q*3.))+vec3(.45,.1,.15)*sheen*.5;c*=.9+.2*noise(u*uR*.5);',
    ' c+=vec3(.5,.25,.2)*smoothstep(.2,1.,u.y)*.35*exp(-length(q-vec2(0.,1.1))*1.5);',
    ' for(int i=0;i<12;i++){float fi=float(i);vec2 p=vec2(hash(vec2(fi,1.))*ar-ar*.5,fract(hash(vec2(fi,2.))+uT*.01*(1.+hash(vec2(fi,3.)))+uP*.3));float r=.02+hash(vec2(fi,4.))*.04;',
    '  c+=vec3(1.,.8,.45)*(disc(q,p,r)*.12+ring(q,p,r)*.2)*(.5+.5*sin(uT*.7+fi*2.));}',
    ' return c;}'
  ].join('\n');

  // Dunes: ridges lit from the side, sand grain, wind, day into night.
  LXSH.dunes = [
    'vec3 scene(vec2 u,float ar){',
    ' float night=smoothstep(.35,.95,uP);vec2 q=vec2((u.x-.5)*ar,u.y);float hz=.5;vec2 sun=vec2(.3*ar,hz+.3-night*.45);',
    ' vec3 top=mix(vec3(.22,.40,.72),vec3(.03,.03,.10),night),low=mix(vec3(.99,.80,.55),vec3(.30,.12,.20),night);vec3 sky=mix(low,top,smoothstep(hz,1.,u.y));sky*=1.-.35*smoothstep(.35,.0,length(vec2(q.x*.8,u.y-.6)))*(1.-night);',
    ' float d=length(q-sun);sky+=mix(vec3(1.,.8,.5),vec3(1.,.5,.2),night)*(.28*exp(-d*9.)+.1*exp(-d*2.))*(1.-night*.6);sky=mix(sky,vec3(1.,.97,.9),smoothstep(.04,.032,d)*(1.-night));',
    ' sky+=vec3(1.)*stars(u,ar,60.)*night*step(hz,u.y);vec2 mo=vec2(-.3*ar,.86);float md=length(q-mo);sky+=vec3(1.,.95,.85)*smoothstep(.045,.04,md)*night+vec3(.8,.85,1.)*exp(-md*6.)*.2*night;',
    ' vec3 c=sky;vec3 sandL=mix(vec3(.98,.76,.45),vec3(.35,.25,.45),night*.8),sandD=mix(vec3(.72,.40,.22),vec3(.12,.08,.2),night*.8);',
    ' for(int i=0;i<5;i++){float fi=float(i);float y0=hz-.02-fi*.11;float fx=u.x*ar*(1.2+fi*.5)+fi*3.1;',
    '  float hgt=.06*sin(fx*1.3)+.03*sin(fx*3.7+1.)+.006*noise(vec2(fx*4.,fi))*(1.+fi);float dh=.078*cos(fx*1.3)+.111*cos(fx*3.7+1.);',
    '  float yr=y0+hgt*(1.+fi*.3);float m=step(u.y,yr);float lit=clamp(.55+dh*2.2,0.,1.);',
    '  float grain=noise(vec2(u.x*ar*180.,u.y*180.))*.08;float rip=.04*sin((u.x*ar*60.+u.y*20.)+fbm3(vec2(u.x*ar*5.,u.y*5.))*8.);',
    '  vec3 sc=mix(sandD,sandL,clamp(lit*.8+grain+rip,0.,1.));sc+=vec3(1.,.9,.7)*smoothstep(.008,0.,yr-u.y)*.3*(1.-night);sc*=1.-.35*smoothstep(.03,0.,yr-u.y)*step(dh,0.);sc=mix(sc,low*.9,pow(1.-fi/5.,2.)*.3);c=mix(c,sc,m);}',
    ' float st=pow(noise(vec2(u.x*ar*25.-uT*3.,u.y*220.)),8.)*smoothstep(.55,.2,u.y)*step(u.y,hz);c+=vec3(1.,.85,.6)*st*.5*(1.-night*.5);return c;}'
  ].join('\n');

  // Rivage: a sunset sea with real wave shading, sun glitter, foam, wet sand.
  LXSH.rivage = [
    'vec3 scene(vec2 u,float ar){',
    ' float hz=.55;vec2 q=vec2((u.x-.5)*ar,u.y);vec2 sun=vec2(.05*ar,hz+.08-uP*.1);vec3 top=vec3(.30,.35,.62),low=vec3(.99,.70,.45);',
    ' vec3 sky=mix(low,top,smoothstep(hz,1.,u.y));float cl=fbm3(vec2(u.x*ar*2.+uT*.01,u.y*5.));sky=mix(sky,vec3(.9,.55,.5),smoothstep(.5,.8,cl)*smoothstep(hz,hz+.3,u.y)*.5);',
    ' float d=length(q-sun);sky+=vec3(1.,.75,.45)*(.6*exp(-d*6.)+.25*exp(-d*1.5));sky=mix(sky,vec3(1.,.95,.85),smoothstep(.06,.05,d));vec3 c=sky;',
    ' if(u.y<hz){float dep=(hz-u.y)/hz;float pz=.04+dep*1.8;vec2 wp=vec2((u.x-.5)*ar/pz,1./pz)*1.5;float h=0.;vec2 g=vec2(0.);',
    '  for(int i=0;i<6;i++){float fi=float(i);vec2 k=vec2(cos(fi*1.7+.3),sin(fi*1.7+.3))*(1.+fi*1.1);float ph=dot(k,wp)-uT*(.9+fi*.35);float a=.35/(1.+fi*.8);h+=a*sin(ph);g+=a*cos(ph)*k;}',
    '  vec3 n=normalize(vec3(-g.x*.6,1.,-g.y*.6));vec3 wat=mix(vec3(.05,.22,.3),vec3(.15,.5,.55),smoothstep(.0,.8,dep)*.6+h*.3);',
    '  float fr=pow(max(0.,1.-n.y),1.5)*.6+.2;vec3 col=mix(wat,mix(low,top,.3),fr*(1.-dep*.4));',
    '  vec3 ld=normalize(vec3(sun.x-q.x,.25,1.));vec3 vd=normalize(vec3(0.,.5,-1.));float sp=pow(max(dot(reflect(vd,n),ld),0.),120.);float bx=(q.x-sun.x)*2.5;float band=exp(-bx*bx);',
    '  col+=vec3(1.,.85,.6)*sp*band*1.8*(1.-dep*.5);',
    '  float fm=smoothstep(.58,.85,fbm3(wp*.4+uT*.15+h*2.))*smoothstep(.45,.9,dep);col=mix(col,vec3(.95,.97,.98),fm*.8);',
    '  float sand=smoothstep(.86,1.,dep);vec3 sc=mix(vec3(.75,.6,.45),low,.4)*(.9+.1*noise(u*uR*.3));sc+=vec3(1.,.8,.5)*band*.3;',
    '  col=mix(col,sc,sand*smoothstep(.3,.7,noise(vec2(u.x*ar*6.,uT*.2))+.3));c=col;}',
    ' return c;}'
  ].join('\n');

  // Champagne: amber liquid, caustic light, bubbles rising, warm bokeh.
  LXSH.champagne = [
    'vec3 scene(vec2 u,float ar){',
    ' vec2 q=vec2((u.x-.5)*ar,u.y);vec3 amber=mix(vec3(.95,.72,.30),vec3(.5,.3,.08),clamp(u.y*1.4-.1,0.,1.));vec3 c=amber*(.7+.3*fbm3(q*2.+uT*.05));',
    ' float ca=pow(1.-abs(sin(fbm3(q*3.+vec2(0.,-uT*.25))*9.)),5.);c+=vec3(1.,.9,.6)*ca*.3;',
    ' for(int k=0;k<3;k++){float fk=float(k);float sc=8.+fk*7.;float sp=.25+fk*.18;vec2 p=vec2(q.x,q.y-uT*sp-uP*.5)*sc;vec2 i=floor(p);vec2 f=fract(p);float hh=hash(i+fk*7.3);',
    '  if(hh>.45){vec2 cen=vec2(.5+(hash(i+1.1)-.5)*.5+sin(uT*2.+hh*20.)*.06,.5+(hash(i+2.2)-.5)*.5);float r=.12+hash(i+3.3)*.14;float d=length(f-cen);',
    '   float rg=smoothstep(.03,.0,abs(d-r))*.9;float body=smoothstep(r,r-.05,d)*.12;float hl=smoothstep(.06,.0,length(f-cen+vec2(r*.45,r*.45)))*1.2;',
    '   c+=vec3(1.,.95,.8)*(rg*.5+body+hl)*(.45+.55*(1.-fk/3.));}}',
    ' for(int i=0;i<10;i++){float fi=float(i);vec2 p=vec2(hash(vec2(fi,1.))*ar-ar*.5,.6+hash(vec2(fi,2.))*.5);float r=.05+hash(vec2(fi,3.))*.06;c+=vec3(1.,.9,.6)*(disc(q,p,r)*.15+ring(q,p,r)*.25)*(.6+.4*sin(uT+fi));}',
    ' c*=smoothstep(1.,.42,u.y)*.9+.1;c+=vec3(.9,.7,.35)*.06*smoothstep(.4,1.,u.y);return c;}'
  ].join('\n');

  // Herbier: old paper, fibres, foxing, sunlight through leaves.
  LXSH.herbier = [
    'vec3 scene(vec2 u,float ar){',
    ' vec2 q=vec2((u.x-.5)*ar,u.y);vec3 c=vec3(.95,.90,.78);c*=.92+.08*fbm3(q*6.);c*=.95+.05*noise(vec2(u.x*ar*300.,u.y*40.));',
    ' float spots=smoothstep(.62,.75,fbm(q*2.5+3.));c=mix(c,vec3(.78,.66,.45),spots*.25);',
    ' float sh=fbm3(vec2(q.x*2.+uT*.05,q.y*3.+uT*.03));c*=.85+.25*smoothstep(.35,.7,sh);',
    ' c+=vec3(1.,.95,.8)*.08*smoothstep(.8,0.,length(q-vec2(.3*ar,.85)));c*=1.-.25*pow(max(abs(u.x-.5)*2.,abs(u.y-.5)*2.),6.);return c;}'
  ].join('\n');

  // Givre: a winter night behind glass; frost crystals grow in from the edges as you scroll.
  LXSH.givre = [
    'vec3 scene(vec2 u,float ar){',
    ' vec2 q=vec2((u.x-.5)*ar,u.y);vec3 c=mix(vec3(.03,.05,.13),vec3(.07,.11,.24),u.y);c+=vec3(1.,.98,.9)*stars(u,ar,80.)*.7*smoothstep(.4,.9,u.y);',
    ' vec2 mo=vec2(.25*ar,.8);float md=length(q-mo);c+=vec3(1.,.97,.9)*smoothstep(.06,.055,md)*.9+vec3(.6,.7,1.)*exp(-md*4.)*.3;',
    ' for(int i=0;i<14;i++){float fi=float(i);vec2 p=vec2(hash(vec2(fi,1.))*ar-ar*.5,.12+hash(vec2(fi,2.))*.22);float r=.015+hash(vec2(fi,3.))*.03;float d=length(q-p);c+=vec3(1.,.75,.4)*exp(-d*d/(r*r))*.9*(.7+.3*sin(uT*2.+fi*3.));}',
    ' float gr=smoothstep(.2,.0,u.y+noise(vec2(u.x*ar*4.,1.))*.05);c=mix(c,vec3(.75,.8,.9),gr);',
    ' float s=0.;for(int k=0;k<4;k++){float fk=float(k);float sc=8.+fk*9.;vec2 p=vec2(q.x+sin(uT*.3+fk)*.05,q.y+uT*(.03+fk*.03)+uP*.6*(.3+fk*.2))*sc;vec2 i=floor(p),f=fract(p);vec2 cen=vec2(hash(i+fk),hash(i+fk+5.));float d=length(f-cen);s+=smoothstep(.035+fk*.012,.0,d)*(.3+fk*.15)*step(.74,hash(i+fk*2.3));}',
    ' c+=vec3(1.)*s;',
    ' float edge=min(min(u.x,1.-u.x)*ar*2.,min(u.y,1.-u.y)*1.4);float grow=.06+uP*.5;float fr=fbm(q*7.+vec2(uT*.01,0.));float fm=smoothstep(grow+.07,grow-.07,edge+fr*.28-.12);',
    ' float cry=pow(noise(q*120.),6.)*2.;float fern=pow(1.-abs(sin(fbm3(q*25.)*12.)),8.);vec3 fc=mix(vec3(.6,.74,.95),vec3(.95,.98,1.),cry+fern*.5);',
    ' c=mix(c,c*.35+fc*.65,fm*.8);c+=vec3(1.)*fm*cry*.4*(.5+.5*sin(uT*3.+fr*30.));return c;}'
  ].join('\n');

  // Grand soir: a city at night, smoke in the sky, the water that will mirror the fireworks.
  LXSH.feux = [
    'vec3 scene(vec2 u,float ar){',
    ' float wl=.22;vec2 q=vec2((u.x-.5)*ar,u.y);vec3 c=mix(vec3(.04,.03,.10),vec3(.01,.01,.04),smoothstep(wl,1.,u.y));',
    ' float smoke=fbm(vec2(q.x*1.5+uT*.03,q.y*2.-uT*.02));c+=vec3(.25,.18,.3)*smoothstep(.45,.8,smoke)*.35*step(wl,u.y);c+=vec3(1.)*stars(u,ar,60.)*.5*step(wl+.1,u.y);',
    ' float bx=u.x*ar*14.;float bh=wl+.03+hash(vec2(floor(bx),1.))*.14;float bld=step(u.y,bh)*step(wl,u.y);vec3 bc=vec3(.02,.02,.05);',
    ' float win=step(.72,hash(vec2(floor(bx*4.),floor(u.y*120.))))*step(fract(bx*4.),.5)*step(fract(u.y*120.),.5)*step(u.y,bh-.01);c=mix(c,bc,bld);c+=vec3(1.,.8,.5)*win*bld*.8;',
    ' if(u.y<wl){float w=sin(u.x*ar*40.+uT*2.)*.5+sin(u.x*ar*17.-uT*1.3)*.5;vec2 ru=vec2(u.x,2.*wl-u.y+w*.006);float bx2=ru.x*ar*14.;float bh2=wl+.03+hash(vec2(floor(bx2),1.))*.14;float bld2=step(ru.y,bh2);',
    '  float win2=step(.72,hash(vec2(floor(bx2*4.),floor(ru.y*120.))))*step(fract(bx2*4.),.5)*step(fract(ru.y*120.),.5)*step(ru.y,bh2-.01);vec3 rc=mix(vec3(.04,.03,.10),bc,bld2)+vec3(1.,.8,.5)*win2*bld2*.5;',
    '  c=mix(rc*.6,vec3(.01,.01,.03),.3)+vec3(.1,.08,.15)*pow(max(0.,w),4.)*.3;}',
    ' return c;}'
  ].join('\n');

  // Boréale: curtains of aurora over snowy mountains, mirrored in a lake.
  LXSH.aurore = [
    'vec3 aur(vec2 u,float ar,float full){vec3 au=vec3(0.);for(int i=0;i<3;i++){float fi=float(i);float y0=.5+fi*.1+.1*sin(u.x*ar*2.2+uT*.25+fi*2.)+fbm3(vec2(u.x*ar*1.3+uT*.05,fi))*.15;float dy=u.y-y0;',
    ' float streak=full>.5?noise(vec2(u.x*ar*30.+uT*.4+fi*9.,u.y*3.))*.6+noise(vec2(u.x*ar*90.-uT*.3,u.y*2.))*.4:noise(vec2(u.x*ar*30.+uT*.4+fi*9.,u.y*3.))*.6+.4;',
    ' float band=exp(-max(dy,0.)*8.)*smoothstep(-.03,.03,dy)*exp(-abs(dy)*2.);float inten=band*streak*(.6+.4*sin(uT*.6+fi+u.x*5.))*(.6+uP*.6);',
    ' au+=mix(vec3(.1,.95,.5),vec3(.55,.25,.9),clamp(dy*4.,0.,1.))*inten*(1.-fi*.25);}return au;}',
    'vec3 scene(vec2 u,float ar){',
    ' float wl=.3;vec2 q=vec2((u.x-.5)*ar,u.y);vec3 c=mix(vec3(.02,.04,.10),vec3(.0,.01,.04),smoothstep(wl,1.,u.y));',
    ' float mh=wl+.1+.1*noise(vec2(u.x*ar*2.5,1.))+.05*noise(vec2(u.x*ar*7.,2.))+.02*noise(vec2(u.x*ar*20.,3.));',
    ' vec3 au=aur(u,ar,1.);c+=au*step(mh,u.y);c+=vec3(1.)*stars(u,ar,90.)*.8*step(mh,u.y);',
    ' float mt=step(u.y,mh)*step(wl,u.y);vec3 mc=mix(vec3(.03,.05,.09),vec3(.2,.3,.35),smoothstep(mh-.06,mh,u.y))*(.6+.4*au.g);',
    ' mc+=vec3(.5,.6,.7)*smoothstep(.0,.03,u.y-(mh-.05))*step(.55,noise(vec2(u.x*ar*40.,u.y*40.)))*.6;c=mix(c,mc,mt);',
    ' if(u.y<wl){float w=sin(u.x*ar*30.+uT*1.5)*.004+sin(u.x*ar*11.-uT)*.004;vec2 ru=vec2(u.x,2.*wl-u.y+w);vec3 au2=aur(ru,ar,0.);',
    '  float mh2=wl+.1+.1*noise(vec2(ru.x*ar*2.5,1.))+.05*noise(vec2(ru.x*ar*7.,2.));vec3 rc=mix(vec3(.02,.04,.10),vec3(.03,.05,.09),step(ru.y,mh2))+au2*step(mh2,ru.y)*.6;c=mix(rc*.7,vec3(.01,.02,.05),.3);}',
    ' return c;}'
  ].join('\n');

  // ================= Premium: the foreground, drawn by hand on a 2D canvas =================
  // Shaded petals, wings, lanterns, flakes and sparks with depth of field. Each drawer returns
  // {draw(g,w,h,t,gp,dpr,vel), stop()} and only draws what the shader cannot.
  var LXFX = {};
  function sprite(kind, col) {
    var S = 96, c = document.createElement('canvas'); c.width = c.height = S; var g = c.getContext('2d'), m = S / 2;
    if (kind === 'petal') {
      var gr = g.createLinearGradient(m, 8, m, S - 8); gr.addColorStop(0, rgb(mix(col, [255, 255, 255], .55))); gr.addColorStop(1, rgb(col)); g.fillStyle = gr;
      g.beginPath(); g.moveTo(m, S - 10); g.bezierCurveTo(S - 6, m + 10, S - 18, 10, m + 6, 14); g.lineTo(m, 22); g.lineTo(m - 6, 14); g.bezierCurveTo(18, 10, 6, m + 10, m, S - 10); g.fill();
      g.strokeStyle = 'rgba(255,255,255,.35)'; g.lineWidth = 1.2; g.beginPath(); g.moveTo(m, S - 14); g.quadraticCurveTo(m + 3, m, m, 26); g.stroke();
    } else if (kind === 'bubble') {
      g.strokeStyle = 'rgba(255,248,230,.75)'; g.lineWidth = 2.5; g.beginPath(); g.arc(m, m, m - 6, 0, TAU); g.stroke();
      var rg = g.createRadialGradient(m - 14, m - 14, 1, m - 14, m - 14, 16); rg.addColorStop(0, 'rgba(255,255,255,.95)'); rg.addColorStop(1, 'rgba(255,255,255,0)'); g.fillStyle = rg; g.fillRect(0, 0, S, S);
    } else if (kind === 'snow') {
      var sg = g.createRadialGradient(m, m, 0, m, m, m); sg.addColorStop(0, 'rgba(255,255,255,1)'); sg.addColorStop(.35, 'rgba(255,255,255,.85)'); sg.addColorStop(1, 'rgba(255,255,255,0)'); g.fillStyle = sg; g.fillRect(0, 0, S, S);
    } else {
      var bg = g.createRadialGradient(m, m, 0, m, m, m), hard = kind === 'bokeh' || kind === 'glow';
      bg.addColorStop(0, rgb(mix(col, [255, 255, 255], .5), 1)); bg.addColorStop(hard ? .55 : .25, rgb(col, hard ? .55 : .6)); bg.addColorStop(hard ? .72 : 1, rgb(col, hard ? .35 : 0)); bg.addColorStop(1, rgb(col, 0)); g.fillStyle = bg; g.fillRect(0, 0, S, S);
    }
    return c;
  }
  function particles(kind, col, count) {
    var sp = sprite(kind, col), soft = sprite(kind === 'petal' ? 'dust' : kind, col), R = rng(7), P2 = [];
    var n = count || {petal: 30, dust: 50, glow: 22, sand: 80, glint: 36, bubble: 36, bokeh: 18, snow: 90, ember: 60}[kind] || 36;
    for (var i = 0; i < n; i++) P2.push({x: R(), y: R(), z: .15 + R() * .85, ph: R() * TAU, v: .5 + R(), r: R() * TAU});
    return function (g, w, h, t, gp, dpr) {
      P2.forEach(function (p) {
        var z = p.z, size = (kind === 'snow' ? 6 : kind === 'sand' ? 3 : kind === 'bokeh' ? 60 : kind === 'glow' ? 46 : kind === 'bubble' ? 16 : kind === 'petal' ? 26 : 10) * (.35 + z * 1.1) * dpr;
        var x, y, a = 1, rot = 0;
        if (kind === 'petal') { x = ((p.x + t * .025 * p.v + Math.sin(t * .6 + p.ph) * .03 + gp * .3 * z) % 1.2 - .1) * w; y = ((p.y + t * .035 * p.v * (.5 + z) + gp * .8 * z) % 1.2 - .1) * h; rot = t * p.v + p.ph; }
        else if (kind === 'snow') { x = ((p.x + Math.sin(t * .4 * p.v + p.ph) * .03) % 1) * w; y = ((p.y + t * .05 * (.3 + z) + gp * 1.2 * z) % 1.1 - .05) * h; a = .5 + .5 * z; }
        else if (kind === 'bubble') { x = (p.x + Math.sin(t * 2 * p.v + p.ph) * .01) * w; y = (1.1 - ((p.y + t * .06 * p.v * (.4 + z) + gp * .6) % 1.2)) * h; a = .8; }
        else if (kind === 'ember') { x = ((p.x + Math.sin(t * .9 + p.ph) * .02) % 1) * w; y = ((p.y + t * .03 * p.v + gp * .9 * z) % 1.1) * h; a = .3 + .7 * Math.abs(Math.sin(t * 3 * p.v + p.ph)); }
        else if (kind === 'glow') { x = (p.x + Math.sin(t * .2 + p.ph) * .04) * w; y = (1.1 - ((p.y + t * .02 * p.v * (.3 + z) + gp * .5 * z) % 1.2)) * h; a = (.5 + .5 * Math.sin(t * 5 + p.ph)) * .5 + .3; }
        else if (kind === 'sand') { x = ((p.x + t * .12 * p.v * (.4 + z) + gp * .4) % 1.1 - .05) * w; y = (p.y * .6 + .4 + Math.sin(t * 2 + p.x * 20) * .01) * h; a = .5 * z; }
        else { x = ((p.x + Math.sin(t * .15 * p.v + p.ph) * .05 + gp * .1 * z) % 1) * w; y = ((p.y - t * .008 * p.v - gp * .5 * z) % 1 + 1) % 1 * h; a = (kind === 'bokeh' ? .22 : .55) * (.4 + .6 * Math.abs(Math.sin(t * .7 * p.v + p.ph))) * (kind === 'glint' ? Math.max(0, Math.sin(t * 2.5 * p.v + p.ph)) : 1); }
        g.globalAlpha = a * (z < .35 && kind !== 'bokeh' ? .55 : 1);
        var img = z < .3 || z > .92 ? soft : sp;
        g.save(); g.translate(x, y); if (rot) { g.rotate(rot); g.scale(1, .6 + .4 * Math.cos(t * 2 * p.v + p.ph)); }
        g.drawImage(img, -size / 2, -size / 2, size, size); g.restore();
      });
      g.globalAlpha = 1;
    };
  }
  function softShadow(g, x, y, rx, ry, a) { var gr = g.createRadialGradient(x, y, 0, x, y, rx); gr.addColorStop(0, 'rgba(0,0,0,' + a + ')'); gr.addColorStop(1, 'rgba(0,0,0,0)'); g.save(); g.translate(x, y); g.scale(1, ry / rx); g.translate(-x, -y); g.fillStyle = gr; g.fillRect(x - rx, y - rx, rx * 2, rx * 2); g.restore(); }

  // A rose seen from above: six layers of cupped petals, dark at the heart, lit at the rim.
  function drawRose(g, x, y, R, open, rot, cols) {
    var layers = [[7, 1], [7, .86], [6, .72], [6, .58], [5, .45], [5, .33]];
    g.save(); g.translate(x, y); g.rotate(rot);
    layers.forEach(function (L, li) {
      var n = L[0], rr = R * L[1] * (.3 + .7 * open), rotL = li * .47 + (1 - open) * li * .35;
      for (var i = 0; i < n; i++) {
        g.save(); g.rotate(i / n * TAU + rotL);
        var w = rr * .62 * (.8 + .2 * open), hh = rr;
        var p = new Path2D(); p.moveTo(0, 0); p.bezierCurveTo(w * 1.1, -hh * .15, w * 1.05, -hh * .95, w * .15, -hh); p.bezierCurveTo(w * .05, -hh * 1.03, -w * .05, -hh * 1.03, -w * .15, -hh); p.bezierCurveTo(-w * 1.05, -hh * .95, -w * 1.1, -hh * .15, 0, 0);
        var gr = g.createRadialGradient(0, -hh * .1, hh * .05, 0, -hh * .45, hh * .95); gr.addColorStop(0, cols[0]); gr.addColorStop(.45, cols[1]); gr.addColorStop(.85, cols[2]); gr.addColorStop(1, cols[3]);
        g.fillStyle = gr; g.fill(p);
        var sh = g.createLinearGradient(0, 0, 0, -hh * .55); sh.addColorStop(0, 'rgba(30,0,8,.6)'); sh.addColorStop(1, 'rgba(30,0,8,0)'); g.fillStyle = sh; g.fill(p);
        g.strokeStyle = 'rgba(255,200,205,.45)'; g.lineWidth = Math.max(1, rr * .018); g.stroke(p);
        g.restore();
      }
    });
    g.strokeStyle = cols[0]; g.lineWidth = R * .045; g.beginPath();
    for (var a = 0; a < TAU * 2.2; a += .15) { var r = R * .02 + a * R * .022 * (.3 + .7 * open); g.lineTo(Math.cos(a) * r, Math.sin(a) * r * .8); } g.stroke();
    g.restore();
  }
  // A lotus: pointed petals, white to pink, a golden heart.
  function drawLotus(g, x, y, R, open, rot) {
    g.save(); g.translate(x, y); g.rotate(rot);
    [[8, 1, .55], [8, .8, .75], [7, .58, 1]].forEach(function (L, li) {
      var n = L[0], rr = R * L[1] * (.35 + .65 * open), lift = L[2];
      for (var i = 0; i < n; i++) {
        g.save(); g.rotate(i / n * TAU + li * .39); g.scale(1, lift + (1 - lift) * (1 - open));
        var w = rr * .34, p = new Path2D(); p.moveTo(0, 0); p.bezierCurveTo(w * 1.2, -rr * .3, w * .9, -rr * .85, 0, -rr); p.bezierCurveTo(-w * .9, -rr * .85, -w * 1.2, -rr * .3, 0, 0);
        var gr = g.createLinearGradient(0, 0, 0, -rr); gr.addColorStop(0, '#f7dbe3'); gr.addColorStop(.55, '#fbeef2'); gr.addColorStop(1, '#e8689a');
        g.fillStyle = gr; g.fill(p); g.strokeStyle = 'rgba(200,90,130,.35)'; g.lineWidth = 1; g.stroke(p);
        var sh = g.createLinearGradient(0, 0, 0, -rr * .4); sh.addColorStop(0, 'rgba(120,40,70,.35)'); sh.addColorStop(1, 'rgba(120,40,70,0)'); g.fillStyle = sh; g.fill(p);
        g.restore();
      }
    });
    var cg = g.createRadialGradient(0, 0, 0, 0, 0, R * .18); cg.addColorStop(0, '#ffe88a'); cg.addColorStop(1, '#e0a020'); g.fillStyle = cg; g.beginPath(); g.arc(0, 0, R * .17 * open, 0, TAU); g.fill();
    g.fillStyle = 'rgba(120,70,10,.6)'; for (var k = 0; k < 14; k++) { var a2 = k * 2.4, r2 = Math.sqrt(k / 14) * R * .13 * open; g.beginPath(); g.arc(Math.cos(a2) * r2, Math.sin(a2) * r2, R * .014, 0, TAU); g.fill(); }
    g.restore();
  }
  // A sunflower: two rings of petals with shading, a disc of seeds in a spiral.
  function drawSunflower(g, x, y, R, rot, face) {
    g.save(); g.translate(x, y); g.rotate(rot); g.scale(.55 + .45 * face, 1);
    for (var L = 0; L < 2; L++) {
      var n = 19, rr = R * (1 - L * .12);
      for (var i = 0; i < n; i++) {
        g.save(); g.rotate(i / n * TAU + L * TAU / (n * 2));
        var gr = g.createLinearGradient(0, -rr * .42, 0, -rr * 1.05); gr.addColorStop(0, L ? '#b97b0e' : '#e3a016'); gr.addColorStop(.55, L ? '#dfa320' : '#f6c531'); gr.addColorStop(1, L ? '#f0c247' : '#ffe272');
        g.fillStyle = gr; g.beginPath(); g.moveTo(0, -rr * .42); g.quadraticCurveTo(rr * .17, -rr * .7, rr * .06, -rr * 1.02); g.lineTo(0, -rr * 1.07); g.lineTo(-rr * .06, -rr * 1.02); g.quadraticCurveTo(-rr * .17, -rr * .7, 0, -rr * .42); g.fill();
        g.strokeStyle = 'rgba(120,70,0,.3)'; g.lineWidth = .8; g.beginPath(); g.moveTo(0, -rr * .46); g.lineTo(0, -rr); g.stroke(); g.restore();
      }
    }
    var dg = g.createRadialGradient(-R * .1, -R * .1, R * .05, 0, 0, R * .5); dg.addColorStop(0, '#5c3b12'); dg.addColorStop(.7, '#3a2208'); dg.addColorStop(1, '#221204'); g.fillStyle = dg; g.beginPath(); g.arc(0, 0, R * .5, 0, TAU); g.fill();
    var n2 = Math.min(170, Math.floor(R * 1.5));
    for (var k = 0; k < n2; k++) { var r = Math.sqrt(k / n2) * R * .47, a = k * 2.39996, sx = Math.cos(a) * r, sy = Math.sin(a) * r; g.fillStyle = r > R * .38 ? 'rgba(226,176,64,.85)' : 'rgba(125,84,30,.75)'; g.beginPath(); g.arc(sx, sy, R * .015 + r * .012, 0, TAU); g.fill(); g.fillStyle = 'rgba(255,230,150,.3)'; g.beginPath(); g.arc(sx - R * .006, sy - R * .006, R * .007, 0, TAU); g.fill(); }
    g.restore();
  }
  // A butterfly with veined wings, a dark border with white spots, and a body with antennae.
  function drawButterfly(g, x, y, s, flap, rot, main, light, dark) {
    g.save(); g.translate(x, y); g.rotate(rot);
    [-1, 1].forEach(function (sd) {
      g.save(); g.scale(sd * Math.max(.08, flap), 1);
      var fw = new Path2D(); fw.moveTo(0, -s * .05); fw.bezierCurveTo(s * .5, -s * 1.25, s * 1.65, -s * 1.35, s * 1.55, -s * .5); fw.bezierCurveTo(s * 1.45, -s * .08, s * .6, s * .1, 0, s * .08); fw.closePath();
      var hw = new Path2D(); hw.moveTo(0, 0); hw.bezierCurveTo(s * .95, -s * .12, s * 1.3, s * .5, s * .92, s * .98); hw.bezierCurveTo(s * .5, s * 1.15, s * .1, s * .9, 0, s * .3); hw.closePath();
      var gr = g.createLinearGradient(0, 0, s * 1.5, -s * .7); gr.addColorStop(0, dark); gr.addColorStop(.35, main); gr.addColorStop(1, light);
      [fw, hw].forEach(function (p) { g.fillStyle = gr; g.fill(p); g.lineWidth = s * .2; g.strokeStyle = 'rgba(22,14,8,.92)'; g.stroke(p); });
      g.strokeStyle = 'rgba(30,18,8,.6)'; g.lineWidth = s * .05;
      for (var k = 0; k < 4; k++) { g.beginPath(); g.moveTo(0, 0); g.quadraticCurveTo(s * .7, -s * .25 - k * s * .22, s * 1.35 - k * s * .12, -s * 1.08 + k * s * .3); g.stroke(); }
      for (var k2 = 0; k2 < 3; k2++) { g.beginPath(); g.moveTo(0, s * .05); g.quadraticCurveTo(s * .5, s * .2 + k2 * s * .18, s * .95 - k2 * s * .15, s * .9 - k2 * s * .1); g.stroke(); }
      g.fillStyle = 'rgba(255,255,255,.88)';
      for (var q = 0; q < 6; q++) { var a = -1.35 + q * .28; g.beginPath(); g.arc(Math.cos(a) * s * 1.48, Math.sin(a) * s * 1.1 - s * .18, s * .055, 0, TAU); g.fill(); }
      for (var q2 = 0; q2 < 4; q2++) { var a2 = .3 + q2 * .3; g.beginPath(); g.arc(Math.cos(a2) * s * 1.12, Math.sin(a2) * s * 1.05, s * .045, 0, TAU); g.fill(); }
      g.restore();
    });
    var bg = g.createLinearGradient(-s * .1, 0, s * .1, 0); bg.addColorStop(0, '#1a110a'); bg.addColorStop(.5, '#3a2a1a'); bg.addColorStop(1, '#120b06'); g.fillStyle = bg;
    g.beginPath(); g.ellipse(0, s * .1, s * .09, s * .62, 0, 0, TAU); g.fill(); g.beginPath(); g.arc(0, -s * .55, s * .1, 0, TAU); g.fill();
    g.strokeStyle = '#1a110a'; g.lineWidth = s * .035; [-1, 1].forEach(function (sd) { g.beginPath(); g.moveTo(0, -s * .6); g.quadraticCurveTo(sd * s * .25, -s * .95, sd * s * .4, -s * 1.05); g.stroke(); g.beginPath(); g.arc(sd * s * .4, -s * 1.05, s * .04, 0, TAU); g.fill(); });
    g.restore();
  }
  // A paper lantern: warm gradient, ribs, gold caps, a flame that flickers.
  function drawLantern(g, x, y, w, h, flick, col) {
    g.save(); g.translate(x, y);
    var gr = g.createRadialGradient(-w * .2, -h * .1, w * .1, 0, 0, w * .9); gr.addColorStop(0, rgb(mix(col, [255, 240, 200], .5), .98)); gr.addColorStop(.6, rgb(col, .96)); gr.addColorStop(1, rgb(mix(col, [120, 40, 10], .55), .96));
    g.fillStyle = gr; var p = new Path2D(); p.moveTo(-w * .32, -h / 2); p.bezierCurveTo(-w * .62, -h * .3, -w * .62, h * .3, -w * .32, h / 2); p.lineTo(w * .32, h / 2); p.bezierCurveTo(w * .62, h * .3, w * .62, -h * .3, w * .32, -h / 2); p.closePath(); g.fill(p);
    g.strokeStyle = 'rgba(120,40,10,.35)'; g.lineWidth = 1; for (var i = 1; i < 6; i++) { var yy = -h / 2 + i * h / 6, ww = w * (.32 + .3 * Math.sin(i / 6 * Math.PI)); g.beginPath(); g.moveTo(-ww, yy); g.lineTo(ww, yy); g.stroke(); }
    g.fillStyle = 'rgba(255,235,180,' + (.25 + .25 * flick) + ')'; g.beginPath(); g.ellipse(0, h * .15, w * .22, h * .25, 0, 0, TAU); g.fill();
    g.fillStyle = '#c99a3a'; g.fillRect(-w * .34, -h / 2 - 4, w * .68, 5); g.fillRect(-w * .34, h / 2 - 1, w * .68, 5);
    g.strokeStyle = '#c99a3a'; g.lineWidth = 1.5; g.beginPath(); g.moveTo(0, h / 2 + 4); g.lineTo(0, h / 2 + 18); g.stroke(); g.fillStyle = '#b3302a'; g.fillRect(-3, h / 2 + 18, 6, 12);
    g.restore();
  }
  // A six-fold snowflake, drawn with branches and a soft halo.
  function drawFlake(g, x, y, r, rot, a, seed) {
    g.save(); g.translate(x, y); g.rotate(rot); g.globalAlpha = a; g.strokeStyle = '#fff'; g.lineCap = 'round';
    for (var i = 0; i < 6; i++) {
      g.rotate(TAU / 6); g.lineWidth = r * .08; g.beginPath(); g.moveTo(0, 0); g.lineTo(0, -r); g.stroke(); g.lineWidth = r * .05;
      for (var k = 1; k < 4; k++) { var yy = -r * (.25 + k * .2), ln = r * (.32 - k * .07) * (.7 + .3 * ((seed * 7 + k) % 3) / 2); g.beginPath(); g.moveTo(0, yy); g.lineTo(ln * .7, yy - ln * .6); g.moveTo(0, yy); g.lineTo(-ln * .7, yy - ln * .6); g.stroke(); }
    }
    g.fillStyle = 'rgba(255,255,255,.9)'; g.beginPath(); g.arc(0, 0, r * .12, 0, TAU); g.fill(); g.restore();
  }
  function fernFrond(g, x0, y0, a, L, t, col, ph) {
    var sw = Math.sin(t * .9 + ph) * .05, ex = x0 + Math.cos(a + sw) * L, ey = y0 + Math.sin(a + sw) * L;
    g.strokeStyle = col; g.lineWidth = 2; g.beginPath(); g.moveTo(x0, y0); g.quadraticCurveTo(x0 + Math.cos(a) * L * .6, y0 + Math.sin(a) * L * .4, ex, ey); g.stroke(); g.fillStyle = col;
    for (var q = 1; q < 14; q++) { var u = q / 14, qx = x0 + (ex - x0) * u, qy = y0 + (ey - y0) * u, ll = L * .14 * (1 - u * .7); g.beginPath(); g.ellipse(qx, qy, ll, ll * .28, a + 1.1, 0, TAU); g.ellipse(qx, qy, ll, ll * .28, a - 1.1, 0, TAU); g.fill(); }
  }
  // ---- per template ----
  LXFX.savane = function (o) {
    var R = rng(3), w = o.w, h = o.h, grass = grassField(R, w, h, Math.round(w / 2.2), .04, .1), dust = particles('dust', [255, 214, 150]), fl = [], trees = null, tH = 0;
    for (var f = 0; f < 3; f++) fl.push({o: R(), y: .14 + R() * .2, n: 4 + (R() * 3 | 0), sp: .012 + R() * .01});
    var TR = [{x: .04, s: .4, seed: 11}, {x: .96, s: .32, seed: 12}, {x: .64, s: .15, seed: 13}, {x: .4, s: .09, seed: 14}];
    return {draw: function (g, w, h, t, gp, dpr, vel) {
      g.clearRect(0, 0, w, h); var day = 1 - sstep(.05, .9, gp), hz = h * .64;
      if (!trees || tH !== h) { tH = h; trees = TR.map(function (tr) { var S = Math.round(h * tr.s); return {c: paintAcacia(S, tr.seed, '#1a1008'), S: S}; }); }
      TR.forEach(function (tr, i) { var c = trees[i], sw = Math.sin(t * .45 + i * 1.7) * .012 + vel * .02; g.save(); g.globalAlpha = .96 - i * .07; g.translate(tr.x * w, hz + c.S * .01); g.transform(1, 0, sw, 1, 0, 0); g.drawImage(c.c, -c.S / 2, -c.S * .985); g.restore(); });
      fl.forEach(function (q) { var bx = ((t * q.sp + q.o) % 1.3 - .15) * w; for (var b = 0; b < q.n; b++) bird(g, bx - b * 16 * dpr, h * q.y + Math.abs(b - q.n / 2) * 7 * dpr, 7 * dpr, Math.sin(t * 7 + b), 'rgba(40,25,15,.7)'); });
      drawGrass(g, grass, h, t, rgb(mix([235, 190, 100], [40, 25, 20], 1 - day), .9), rgb(mix([200, 140, 60], [25, 15, 12], 1 - day), .85), Math.sin(t * .4) * .5 + vel * 1.5);
      dust(g, w, h, t, gp, dpr);
    }};
  };
  LXFX.lotus = function (o) {
    var R = rng(5), koi = [], drag = {ph: 1.3};
    for (var j = 0; j < 3; j++) koi.push({cx: .25 + R() * .5, cy: .25 + R() * .5, rx: .2 + R() * .2, ry: .15 + R() * .2, sp: .07 + R() * .05, ph: R() * TAU, s: 18 + R() * 10, c: j % 2 ? [245, 120, 40] : [250, 245, 235]});
    return {draw: function (g, w, h, t, gp, dpr) {
      g.clearRect(0, 0, w, h); var s0 = dpr;
      koi.forEach(function (f) {
        var a = t * f.sp * TAU * .3 + f.ph, x = w * (f.cx + Math.cos(a) * f.rx), y = h * (f.cy + Math.sin(a * 1.3) * f.ry), dx = -Math.sin(a) * f.rx * w, dy = Math.cos(a * 1.3) * 1.3 * f.ry * h, hd = Math.atan2(dy, dx), s = f.s * s0;
        softShadow(g, x + 6 * s0, y + 12 * s0, s * 2.4, s * 1, .35);
        g.save(); g.translate(x, y); g.rotate(hd);
        for (var sg = 8; sg >= 0; sg--) { var u = sg / 8, ox = -u * s * 2.2, oy = Math.sin(t * 5 - u * 3) * s * .18 * u, rr = s * .42 * (1 - u * .75); var gr = g.createRadialGradient(ox - rr * .3, oy - rr * .4, rr * .1, ox, oy, rr * 1.2); var cc = sg % 3 === 1 ? [250, 248, 240] : f.c; gr.addColorStop(0, rgb(mix(cc, [255, 255, 255], .5))); gr.addColorStop(.7, rgb(cc)); gr.addColorStop(1, rgb(mix(cc, [60, 20, 0], .4))); g.fillStyle = gr; g.beginPath(); g.ellipse(ox, oy, rr * 1.2, rr, 0, 0, TAU); g.fill(); }
        g.fillStyle = rgb(f.c, .75); var tl = Math.sin(t * 5 - 3) * s * .3; g.beginPath(); g.moveTo(-s * 2.1, tl * .6); g.quadraticCurveTo(-s * 2.9, tl - s * .5, -s * 3.1, tl - s * .3); g.lineTo(-s * 2.9, tl); g.lineTo(-s * 3.1, tl + s * .3); g.quadraticCurveTo(-s * 2.9, tl + s * .5, -s * 2.1, tl * .6); g.fill();
        g.fillStyle = rgb(f.c, .6); [-1, 1].forEach(function (sd) { g.beginPath(); g.ellipse(-s * .3, sd * s * .5, s * .5, s * .18, sd * .5 + Math.sin(t * 6) * .2, 0, TAU); g.fill(); });
        g.restore();
      });
      var open = ease((t - .3) / 3) * (.75 + .25 * clamp(gp * 3));
      drawLotus(g, w * .78, h * .83, 92 * s0, open, Math.sin(t * .3) * .05);
      drawLotus(g, w * .16, h * .22 - gp * h * .1, 56 * s0, open * .9, .8 + Math.sin(t * .25) * .05);
      var dx = w * (.5 + .35 * Math.sin(t * .23 + drag.ph)), dy2 = h * (.4 + .2 * Math.sin(t * .37)); g.save(); g.translate(dx, dy2); g.rotate(Math.cos(t * .23) * .5); g.strokeStyle = 'rgba(120,200,220,.55)'; g.lineWidth = 1.5 * s0; var wf = Math.abs(Math.sin(t * 40)); [-1, 1].forEach(function (sd) { g.beginPath(); g.ellipse(0, -2 * s0, 22 * s0 * (.5 + .5 * wf), 5 * s0, sd * .25, 0, TAU); g.stroke(); }); g.fillStyle = 'rgba(40,60,70,.9)'; g.fillRect(-1.5 * s0, -12 * s0, 3 * s0, 30 * s0); g.restore();
    }};
  };
  LXFX.foret = function (o) {
    var R = rng(8), w = o.w, h = o.h, motes = particles('dust', [255, 240, 200], 40), ff = [];
    for (var i = 0; i < 20; i++) ff.push({x: R(), y: .55 + R() * .4, ph: R() * TAU, v: .3 + R() * .5});
    return {draw: function (g, w, h, t, gp, dpr) {
      g.clearRect(0, 0, w, h); motes(g, w, h, t, gp, dpr);
      var col = 'rgba(12,22,14,.95)';
      [[0, -Math.PI / 2 + .25, .22], [0, -Math.PI / 2 + .55, .18], [0, -Math.PI / 2 + .85, .15], [w, -Math.PI / 2 - .3, .2], [w, -Math.PI / 2 - .6, .17], [w, -Math.PI / 2 - .95, .13]].forEach(function (f, i) { fernFrond(g, f[0], h * (1.02 - gp * .06), f[1], h * f[2], t, col, i * 1.3); });
      var night = sstep(.6, 1, gp);
      if (night > .02) ff.forEach(function (f) { var a = night * (.2 + .8 * Math.max(0, Math.sin(t * f.v * 3 + f.ph))); if (a < .03) return; var x = (f.x + Math.sin(t * .3 * f.v + f.ph) * .04) * w, y = (f.y + Math.cos(t * .4 * f.v + f.ph) * .03) * h; glowDot(g, x, y, 10 * dpr, [200, 255, 120], a); });
    }};
  };
  LXFX.cerisiers = function (o) {
    var R = rng(9), pet = particles('petal', [250, 196, 214], 34), tree = makeTree(R, 5, .62), blos = [], cache = document.createElement('canvas'), cg = cache.getContext('2d'), cOpen = -1, cW = 0;
    (function rec(n, x, y, ang, len) { var a = ang + n.a, x2 = x + Math.sin(a) * len, y2 = y - Math.cos(a) * len; n.x = x; n.y = y; n.x2 = x2; n.y2 = y2; n.len = len; if (n.d <= 1) for (var b = 0; b < 5; b++) blos.push({x: x2 + Math.sin(n.ph * 5 + b * 2) * len * .6, y: y2 + Math.cos(n.ph * 3 + b) * len * .6, r: 6 + ((n.ph * 7 + b) % 5), ph: n.ph + b, k: (b + (n.ph * 3 | 0)) % 3}); n.k.forEach(function (c) { rec(c, x2, y2, a, len * c.l); }); })(tree, 0, 0, 0, 1);
    function paint(w, h, dpr, open) {
      cache.width = w; cache.height = h; var g = cg, sc = Math.min(w, h) * .34;
      g.save(); g.translate(-w * .06, h * .06); g.rotate(2.05);
      (function rec(n, depth) { g.strokeStyle = '#2a1b16'; g.lineWidth = Math.max(1, (14 - depth * 2.4) * dpr * .6); g.lineCap = 'round'; g.beginPath(); g.moveTo(n.x * sc, n.y * sc); g.lineTo(n.x2 * sc, n.y2 * sc); g.stroke(); g.strokeStyle = 'rgba(90,70,60,.5)'; g.lineWidth = 1; g.beginPath(); g.moveTo(n.x * sc + 2, n.y * sc); g.lineTo(n.x2 * sc + 2, n.y2 * sc); g.stroke(); n.k.forEach(function (c) { rec(c, depth + 1); }); })(tree, 0);
      blos.forEach(function (b) {
        var x = b.x * sc, y = b.y * sc, r = b.r * dpr * (.4 + .6 * open), cols = [['#ffd9e4', '#f5a3bd', '#d45c86'], ['#fff2f6', '#f8c7d6', '#e07a9c'], ['#ffe3ec', '#f3b0c6', '#cc5a80']][b.k];
        for (var p = 0; p < 5; p++) { g.save(); g.translate(x, y); g.rotate(p / 5 * TAU + b.ph); var gr = g.createRadialGradient(0, -r * .5, 0, 0, -r * .5, r * .7); gr.addColorStop(0, cols[0]); gr.addColorStop(.6, cols[1]); gr.addColorStop(1, cols[2]); g.fillStyle = gr; g.beginPath(); g.ellipse(0, -r * .55, r * .42, r * .6, 0, 0, TAU); g.fill(); g.restore(); }
        g.fillStyle = '#c23b5c'; g.beginPath(); g.arc(x, y, r * .16, 0, TAU); g.fill(); g.fillStyle = 'rgba(255,230,120,.9)'; for (var q = 0; q < 5; q++) { var a = q / 5 * TAU + b.ph; g.beginPath(); g.arc(x + Math.cos(a) * r * .3, y + Math.sin(a) * r * .3, r * .06 + .5, 0, TAU); g.fill(); }
      });
      g.restore();
    }
    return {draw: function (g, w, h, t, gp, dpr) {
      g.clearRect(0, 0, w, h);
      var open = Math.round(ease((t - .2) / 3) * (.75 + .25 * clamp(gp * 2)) * 40) / 40;
      if (open !== cOpen || cW !== w) { paint(w, h, dpr, open); cOpen = open; cW = w; }
      var ox = -w * .06, oy = h * .06 - gp * h * .25;
      g.save(); g.translate(ox, oy); g.rotate(Math.sin(t * .4) * .012); g.translate(-ox, -oy); g.drawImage(cache, 0, oy - h * .06); g.restore();
      pet(g, w, h, t, gp, dpr);
    }};
  };
  LXFX.tournesols = function (o) {
    var R = rng(12), bees = []; for (var b = 0; b < 4; b++) bees.push({ph: R() * TAU, cx: .2 + R() * .6, cy: .35 + R() * .3});
    var fl = [{x: .18, y: 1.02, R: 150, ph: 0}, {x: .82, y: 1.06, R: 125, ph: 2}, {x: .5, y: 1.12, R: 110, ph: 4}];
    var pol = particles('dust', [255, 225, 140], 30);
    return {draw: function (g, w, h, t, gp, dpr) {
      g.clearRect(0, 0, w, h);
      var a = Math.PI * (.15 + .7 * clamp(gp * 1.1)), sunx = w * (.5 - .46 * Math.cos(a)), suny = h * (.52 - .5 * Math.sin(a));
      fl.forEach(function (f, i) {
        var R2 = f.R * dpr * .62, sway = Math.sin(t * .7 + f.ph) * 6 * dpr, hx = f.x * w + sway, hy = f.y * h - R2 * 2.1 - gp * h * .18 * (i === 2 ? 1.5 : 1);
        g.strokeStyle = '#3e6a1e'; g.lineWidth = 7 * dpr * (f.R / 150); g.lineCap = 'round'; g.beginPath(); g.moveTo(f.x * w, f.y * h + 40); g.quadraticCurveTo(f.x * w, hy + R2, hx, hy + R2 * .3); g.stroke();
        g.fillStyle = '#4a7a26'; [[-1, .45], [1, .65]].forEach(function (lf) { var lx = f.x * w + lf[0] * R2 * .2, ly = f.y * h - (hy - f.y * h) * -lf[1]; g.save(); g.translate(f.x * w + sway * lf[1], f.y * h + (hy - f.y * h) * lf[1]); g.rotate(lf[0] * .9 + Math.sin(t + f.ph) * .05); g.beginPath(); g.ellipse(lf[0] * R2 * .45, 0, R2 * .5, R2 * .22, 0, 0, TAU); g.fill(); g.restore(); void lx; void ly; });
        var face = Math.atan2(suny - hy, sunx - hx), fc = .5 + .5 * Math.cos(face + Math.PI / 2);
        softShadow(g, hx + 10 * dpr, hy + 14 * dpr, R2 * 1.05, R2 * .9, .3);
        drawSunflower(g, hx + Math.cos(face) * R2 * .12, hy + Math.sin(face) * R2 * .08, R2, Math.sin(t * .5 + f.ph) * .04 + (face + Math.PI / 2) * .12, fc);
      });
      bees.forEach(function (bz) { var x = w * (bz.cx + .1 * Math.sin(t * 1.7 + bz.ph)), y = h * (bz.cy + .05 * Math.sin(t * 3.1 + bz.ph)), s = dpr; g.fillStyle = '#f2b530'; g.beginPath(); g.ellipse(x, y, 6 * s, 4 * s, 0, 0, TAU); g.fill(); g.fillStyle = '#1a1208'; g.fillRect(x - 1.5 * s, y - 3.5 * s, 2 * s, 7 * s); g.fillRect(x + 2 * s, y - 3 * s, 2 * s, 6 * s); g.fillStyle = 'rgba(255,255,255,.65)'; var fl2 = Math.abs(Math.sin(t * 30 + bz.ph)); g.beginPath(); g.ellipse(x - 1, y - 5 * s, 3.5 * s, (4 * fl2 + .5) * s, 0, 0, TAU); g.fill(); });
      pol(g, w, h, t, gp, dpr);
    }};
  };
  LXFX.lanternes = function (o) {
    var R = rng(14), L = []; for (var i = 0; i < 48; i++) L.push({x: R(), o: R(), sp: .011 + R() * .012, s: .7 + R() * .7, ph: R() * TAU, c: R() < .8 ? [250, 150, 60] : [250, 200, 90]});
    var glow = sprite('glow', [255, 170, 80]);
    return {draw: function (g, w, h, t, gp, dpr) {
      g.clearRect(0, 0, w, h); var wl = h * .7, n = Math.round(10 + clamp(gp) * 38);
      for (var k = 0; k < n; k++) {
        var q = L[k], life = ((q.o + t * q.sp) % 1), y = wl - life * (wl + 120 * dpr), x = q.x * w + Math.sin(t * .4 + q.ph) * 24 * dpr * life, sc = q.s * (1 - life * .5) * dpr, fl = .8 + .2 * Math.sin(t * 9 + q.ph), lw = 26 * sc, lh = 38 * sc;
        g.globalAlpha = .7 * fl; g.drawImage(glow, x - lw * 2.2, y - lw * 2.2, lw * 4.4, lw * 4.4); g.globalAlpha = 1;
        drawLantern(g, x, y, lw, lh, fl, q.c);
        var ry = wl + (wl - y) * .35; if (ry < h) { g.save(); g.globalAlpha = .28 * fl; g.translate(x + Math.sin(t * 3 + k) * 3 * dpr, ry); g.scale(1, -1.6); g.filter = 'none'; drawLantern(g, 0, 0, lw, lh * .8, fl, q.c); g.restore(); }
      }
    }};
  };
  LXFX.roseraie = function (o) {
    var pet = particles('petal', [200, 30, 50], 24), gl = particles('glint', [255, 230, 200], 30);
    var cols = [['#4a0310', '#a80d1c', '#dd2f44', '#f58a94'], ['#5a0d18', '#b8172a', '#e5485a', '#f7a3ab']];
    var roses = [{x: .5, y: .62, R: 135, k: 0, rot: .3, dy: -.35}, {x: .12, y: .18, R: 62, k: 1, rot: -.6, dy: .1, sc: .9}, {x: .9, y: .88, R: 54, k: 0, rot: 1.2, dy: -.05, sc: .8}].map(function (r) { r.cv = document.createElement('canvas'); r.open = -1; return r; });
    return {draw: function (g, w, h, t, gp, dpr) {
      g.clearRect(0, 0, w, h);
      var open = Math.round(ease((t - .2) / 3.2) * (.7 + .3 * clamp(gp * 2.5)) * 40) / 40;
      roses.forEach(function (r, i) {
        var R2 = r.R * dpr, o = open * (r.sc || 1), S = Math.ceil(R2 * 2.3);
        if (r.open !== o || r.cv.width !== S) { r.cv.width = r.cv.height = S; drawRose(r.cv.getContext('2d'), S / 2, S / 2, R2, o, 0, cols[r.k]); r.open = o; }
        var x = w * r.x, y = h * r.y + gp * h * r.dy;
        softShadow(g, x + 12 * dpr, y + 18 * dpr, R2 * 1.1, R2 * .85, .45);
        g.save(); g.translate(x, y); g.rotate(r.rot + Math.sin(t * .2 + i) * .05); g.drawImage(r.cv, -S / 2, -S / 2); g.restore();
      });
      pet(g, w, h, t, gp, dpr); gl(g, w, h, t, gp, dpr);
    }};
  };
  LXFX.dunes = function (o) {
    var sand = particles('sand', [240, 200, 150], 70);
    return {draw: function (g, w, h, t, gp, dpr) {
      g.clearRect(0, 0, w, h); var night = sstep(.35, .95, gp), sil = rgb(mix([60, 35, 25], [15, 10, 20], night)), ry = function (x) { var fx = x / w * (w / h) * 1.7 + 3.1; return h * .52 - (.06 * Math.sin(fx * 1.3) + .03 * Math.sin(fx * 3.7 + 1)) * h * 1.3; };
      for (var c = 0; c < 4; c++) {
        var cx = (1.2 - ((t * .006 + c * .07) % 1.4)) * w, cyy = ry(cx), sc = Math.min(w, h) / 520;
        drawCamel(g, cx, cyy, 34 * sc, t * 2.4 + c * 1.9, sil, c % 2 === 0);
      }
      sand(g, w, h, t, gp, dpr);
    }};
  };
  LXFX.rivage = function (o) {
    var R = rng(16), gulls = [], P1 = makePalm(rng(4), 11), P2 = makePalm(rng(6), 8), gl = particles('glint', [255, 235, 210], 24);
    for (var i = 0; i < 4; i++) gulls.push({o: R(), y: .1 + R() * .22, sp: .015 + R() * .015, s: 6 + R() * 6});
    return {draw: function (g, w, h, t, gp, dpr, vel) {
      g.clearRect(0, 0, w, h);
      var wind = .55 + Math.min(1, Math.abs(vel) * 2.5);
      drawPalm(g, P1, w * .08, h * 1.16, h * .4 + gp * h * .12, t, wind, '#120d08', .38, 20);
      drawPalm(g, P2, w * .97, h * 1.12, h * .3 + gp * h * .08, t + 2, wind, '#1a1410', -.3, 14);
      gulls.forEach(function (q) { bird(g, ((t * q.sp + q.o) % 1.3 - .15) * w, h * q.y + Math.sin(t + q.o * 9) * 6, q.s * dpr, Math.sin(t * 6 + q.o * 20), 'rgba(40,30,40,.75)'); });
      gl(g, w, h, t, gp, dpr);
    }};
  };
  LXFX.champagne = function (o) {
    var bub = particles('bubble', [255, 236, 190], 22), gl = particles('glint', [255, 240, 200], 44);
    return {draw: function (g, w, h, t, gp, dpr) { g.clearRect(0, 0, w, h); bub(g, w, h, t, gp, dpr); gl(g, w, h, t, gp, dpr); }};
  };
  LXFX.herbier = function (o) {
    var R = rng(21), N = 9, B = [], cs = [['#e8892f', '#f7c37a', '#8a3e10'], ['#3b6fd6', '#9ec6ff', '#1a2d6a'], ['#f2c14e', '#fff0b0', '#8a6a10'], ['#e8892f', '#f7c37a', '#8a3e10'], ['#c47ad8', '#efd0f5', '#5a2a70']];
    for (var i = 0; i < N; i++) B.push({x: R() * o.w, y: R() * o.h, vx: 0, vy: 0, c: cs[i % 5], s: 16 + R() * 9, ph: R() * TAU, wx: R(), wy: R(), rest: 0});
    return {draw: function (g, w, h, t, gp, dpr) {
      g.clearRect(0, 0, w, h);
      var act = document.querySelector('.pa-planche[data-active]'), rr = act ? act.getBoundingClientRect() : null;
      B.forEach(function (b, i) {
        var tx, ty, resting = false;
        if (rr && i === 0) { tx = (rr.right - 34) * dpr; ty = (rr.top + 8) * dpr; resting = Math.hypot(tx - b.x, ty - b.y) < 6 * dpr; }
        else { tx = w * (.08 + .84 * Math.abs((b.wx + Math.sin(t * .08 + i) * .35) % 1)); ty = h * (.1 + .75 * Math.abs((b.wy + Math.cos(t * .06 + i * 1.7) * .35) % 1)); }
        b.vx += (tx - b.x) * (resting ? .02 : .003) + Math.sin(t * 2 + b.ph) * .12; b.vy += (ty - b.y) * (resting ? .02 : .003) + Math.cos(t * 1.7 + b.ph) * .12; b.vx *= resting ? .8 : .92; b.vy *= resting ? .8 : .92; b.x += b.vx; b.y += b.vy;
        var s = b.s * dpr, flap = resting ? .55 + .45 * Math.abs(Math.sin(t * 2.5 + b.ph)) : .15 + .85 * Math.abs(Math.sin(t * 10 + b.ph)), ang = resting ? -.4 : Math.atan2(b.vy, b.vx) * .25;
        softShadow(g, b.x + 8 * dpr, b.y + 16 * dpr, s * 1.4 * flap, s * .6, .25);
        drawButterfly(g, b.x, b.y, s, flap, ang, b.c[0], b.c[1], b.c[2]);
      });
    }};
  };
  LXFX.givre = function (o) {
    var R = rng(31), F = []; for (var i = 0; i < 14; i++) F.push({x: R(), y: R(), r: 14 + R() * 26, z: R(), ph: R() * TAU, v: .3 + R() * .5, sd: (R() * 9) | 0});
    return {draw: function (g, w, h, t, gp, dpr) {
      g.clearRect(0, 0, w, h);
      F.forEach(function (f) { var y = ((f.y + t * .018 * f.v + gp * .5 * f.z) % 1.15 - .08) * h, x = (f.x + Math.sin(t * .4 + f.ph) * .04) * w, r = f.r * dpr * (.5 + f.z * .8); if (f.z < .3) { glowDot(g, x, y, r * .45, [255, 255, 255], .25); } else drawFlake(g, x, y, r, t * .2 * f.v + f.ph, .55 + .45 * f.z, f.sd); });
    }};
  };
  LXFX.feux = function (o) {
    var tr = document.createElement('canvas'), tg = tr.getContext('2d'), parts = [], rockets = [], next = .8, R = rng(41), pts = null, phase = 0, w0 = 0;
    var cols = [[255, 214, 110], [255, 255, 255], [255, 120, 140], [120, 200, 255], [255, 170, 60]], sp = sprite('glow', [255, 230, 180]), stop = false;
    function burst(x, y, c, kind, big) {
      var n = kind === 'willow' ? 120 : kind === 'ring' ? 70 : 100 + (big * 60 | 0), spd = (kind === 'willow' ? 3.6 : 2.9 + big * 1.8) * Math.min(w0, 900) / 420;
      for (var i = 0; i < n; i++) { var a = kind === 'ring' ? i / n * TAU : Math.random() * TAU, s = kind === 'ring' ? spd : spd * (.35 + Math.random() * .75); parts.push({x: x, y: y, vx: Math.cos(a) * s, vy: Math.sin(a) * s, l: 1, dl: kind === 'willow' ? .006 : .011 + Math.random() * .006, c: Math.random() < .2 ? cols[1] : c, g: kind === 'willow' ? .07 : .045, cr: kind === 'crackle' && Math.random() < .3}); }
    }
    return {stop: function () { stop = true; }, draw: function (g, w, h, t, gp, dpr) {
      if (tr.width !== w || tr.height !== h) { tr.width = w; tr.height = h; }
      w0 = w; var wl = h * .78;
      tg.globalCompositeOperation = 'destination-out'; tg.fillStyle = 'rgba(0,0,0,.16)'; tg.fillRect(0, 0, w, h);
      tg.globalCompositeOperation = 'lighter';
      // the names, written by sparks, once
      if (!pts && t > .4) {
        var L = lay(), nm = (S.a || 'A') + (S.b && S.b.trim() ? ' & ' + S.b : ''), tx = document.createElement('canvas'); tx.width = w; tx.height = Math.round(h * .3); var tc = tx.getContext('2d');
        var fs = Math.min(w * .17, h * .07); tc.font = '400 ' + fs + 'px ' + (L.fd || 'serif'); tc.textAlign = 'center'; tc.textBaseline = 'middle'; tc.fillStyle = '#fff';
        var mw = tc.measureText(nm).width; if (mw > w * .9) { fs *= w * .9 / mw; tc.font = '400 ' + fs + 'px ' + (L.fd || 'serif'); }
        tc.fillText(nm, w / 2, tx.height / 2); var id = tc.getImageData(0, 0, tx.width, tx.height).data, st = Math.max(3, Math.round(w / 150)); pts = [];
        var nel = document.querySelector('[data-fxn]'), cy = nel ? (nel.getBoundingClientRect().top + nel.getBoundingClientRect().height / 2) * dpr : h * .4;
        for (var yy = 0; yy < tx.height; yy += st) for (var xx = 0; xx < w; xx += st) if (id[(yy * w + xx) * 4 + 3] > 120) pts.push([xx, yy + cy - tx.height / 2]);
        for (var i = pts.length - 1; i > 0; i--) { var j = (R() * (i + 1)) | 0; var tmp = pts[i]; pts[i] = pts[j]; pts[j] = tmp; }
        pts = pts.slice(0, 1100);
        pts.forEach(function (p) { parts.push({x: w / 2, y: h * .9, vx: (Math.random() - .5) * 6, vy: -(9 + Math.random() * 5) * h / 840, l: 1, dl: 0, c: cols[0], g: 0, tx: p[0], ty: p[1], born: t}); });
        phase = 1;
      }
      if (phase === 1 && (t > 5.2 || gp > .03)) { phase = 2; parts.forEach(function (p) { if (p.tx != null) { p.tx = null; p.dl = .012 + Math.random() * .01; p.g = .05; p.vx = (Math.random() - .5) * 3; p.vy = -Math.random() * 2; } }); }
      var every = 1.25 - clamp(gp) * .85;
      if (t > next && phase !== 1) { next = t + every * (.6 + Math.random() * .8); var kinds = ['peony', 'peony', 'willow', 'ring', 'crackle']; rockets.push({x: w * (.15 + Math.random() * .7), y: h * .95, vy: -(h * .012 + Math.random() * h * .004), ty: h * (.12 + Math.random() * .32), c: cols[(Math.random() * cols.length) | 0], k: kinds[(Math.random() * kinds.length) | 0]}); }
      rockets = rockets.filter(function (r) { r.y += r.vy; r.vy *= .985; r.x += Math.sin(t * 20 + r.y) * .3; tg.globalAlpha = .9; tg.drawImage(sp, r.x - 9, r.y - 9, 18, 18); if (r.y <= r.ty) { burst(r.x, r.y, r.c, r.k, gp); return false; } return true; });
      parts = parts.filter(function (p) {
        if (p.tx != null) { var u = clamp((t - p.born - .7) / 1.4); if (u <= 0) { p.x += p.vx; p.y += p.vy; p.vy += .12; } else { var e = 1 - Math.pow(1 - u, 3); p.x += (p.tx - p.x) * (.08 + .3 * e); p.y += (p.ty - p.y) * (.08 + .3 * e); } var tw = .6 + .4 * Math.sin(t * 9 + p.tx); tg.globalAlpha = tw; tg.drawImage(sp, p.x - 5, p.y - 5, 10, 10); return true; }
        p.x += p.vx; p.y += p.vy; p.vy += p.g; p.vx *= .984; p.vy *= .984; p.l -= p.dl; if (p.l <= 0) return false;
        if (p.cr && Math.random() < .08) { tg.globalAlpha = 1; tg.drawImage(sp, p.x - 8, p.y - 8, 16, 16); }
        tg.globalAlpha = p.l; tg.fillStyle = rgb(p.c, p.l); tg.fillRect(p.x - 1.2, p.y - 1.2, 2.4, 2.4); if (p.l > .5) tg.drawImage(sp, p.x - 4, p.y - 4, 8, 8); return true;
      });
      tg.globalAlpha = 1;
      g.clearRect(0, 0, w, h); g.drawImage(tr, 0, 0);
      g.save(); g.beginPath(); g.rect(0, wl, w, h - wl); g.clip(); g.globalAlpha = .32; g.translate(0, 2 * wl); g.scale(1, -1); g.drawImage(tr, Math.sin(t * 2) * 2, 0); g.restore();
    }};
  };
  LXFX.aurore = function (o) {
    var R = rng(51), sn = particles('snow', [255, 255, 255], 36), sh = {t: -9};
    return {draw: function (g, w, h, t, gp, dpr) {
      g.clearRect(0, 0, w, h); sn(g, w, h, t * .4, gp, dpr);
      if (t - sh.t > 6) sh = {t: t, x: .1 + R() * .5, y: .05 + R() * .25}; var u = (t - sh.t) / 1.1;
      if (u < 1) { var x1 = (sh.x + u * .35) * w, y1 = (sh.y + u * .15) * h, gr = g.createLinearGradient(x1 - 140 * dpr, y1 - 60 * dpr, x1, y1); gr.addColorStop(0, 'rgba(255,255,255,0)'); gr.addColorStop(1, 'rgba(255,255,255,' + (1 - u) + ')'); g.strokeStyle = gr; g.lineWidth = 2 * dpr; g.beginPath(); g.moveTo(x1 - 140 * dpr, y1 - 60 * dpr); g.lineTo(x1, y1); g.stroke(); }
    }};
  };

  // ---- a real acacia, painted once: a trunk, forking limbs, a flat feathery crown of leaf clusters ----
  function paintAcacia(S, seed, col) {
    var c = document.createElement('canvas'); c.width = S; c.height = S; var g = c.getContext('2d'), R = rng(seed), bx = S * .5, by = S * .985;
    g.fillStyle = col; g.strokeStyle = col; g.lineCap = 'round'; g.lineJoin = 'round';
    var pts = [], th = S * .39; for (var i = 0; i <= 12; i++) { var u = i / 12, y = by - th * u, w = S * .03 * (1 - u * .5) + (R() - .5) * S * .004, x = bx + Math.sin(u * 2.4) * S * .014; pts.push([x - w, y, x + w, y]); }
    g.beginPath(); pts.forEach(function (p, i) { i ? g.lineTo(p[0], p[1]) : g.moveTo(p[0], p[1]); }); for (var k = pts.length - 1; k >= 0; k--) g.lineTo(pts[k][2], pts[k][3]); g.closePath(); g.fill();
    var tx = (pts[12][0] + pts[12][2]) / 2, ty = pts[12][1];
    function limb(x, y, ang, len, w, d, maxd) {
      var ex = x + Math.sin(ang) * len, ey = y - Math.cos(ang) * len * .62;
      g.lineWidth = w; g.beginPath(); g.moveTo(x, y); g.quadraticCurveTo(x + Math.sin(ang) * len * .5, y - Math.cos(ang) * len * .35 - len * .08, ex, ey); g.stroke();
      if (d < maxd) { var n = 2 + (R() < .55 ? 1 : 0); for (var i = 0; i < n; i++) limb(ex, ey, ang + (i - (n - 1) / 2) * (.5 + R() * .2) + (R() - .5) * .25, len * (.6 + R() * .18), w * .58, d + 1, maxd); }
    }
    limb(tx, ty, 0, S * .17, S * .026, 0, 3);
    [-1.05, -.45, .45, 1.05].forEach(function (a) { limb(tx, ty + S * .02, a, S * .16, S * .018, 0, 2); });
    var cy = ty - S * .24, cw = S * .92;
    for (var j = 0; j < 2600; j++) {
      var u = R() * 2 - 1, edge = Math.sqrt(1 - u * u), xx = bx + u * cw / 2 + (R() - .5) * S * .02, top = cy - edge * S * .06 - R() * S * .012, thick = S * (.035 + .085 * edge) * (.55 + R() * .55), yy = top + Math.pow(R(), .7) * thick;
      g.globalAlpha = .35 + .6 * R(); g.beginPath(); g.ellipse(xx, yy, S * .008 * (.5 + R()), S * .0045 * (.5 + R()), R() * 3.14, 0, TAU); g.fill();
    }
    for (var m = 0; m < 9; m++) { var ux = R() * 2 - 1, ed = Math.sqrt(1 - ux * ux), x0 = bx + ux * cw * .42, y0 = cy + S * .04 * ed; for (var q = 0; q < 90; q++) { g.globalAlpha = .3 + .5 * R(); g.beginPath(); g.ellipse(x0 + (R() - .5) * S * .09, y0 + R() * S * .05 * ed, S * .007, S * .004, R() * 3, 0, TAU); g.fill(); } }
    g.globalAlpha = 1; return c;
  }
  // ---- a coconut palm, drawn live: a ringed trunk, arching fronds of leaflets, wind with lag ----
  function makePalm(R, n) { var fr = []; for (var i = 0; i < n; i++) { var a = -Math.PI * 1.08 + i * (Math.PI * 1.16 / (n - 1)) + (R() - .5) * .22; fr.push({a: a, l: .72 + R() * .36, ph: R() * TAU, droop: .22 + R() * .3, k: R()}); } return fr; }
  function drawPalm(g, fr, bx, by, H, t, wind, col, lean, nl) {
    var cx = bx + lean * H * .45, cy = by - H, prev = null;
    g.strokeStyle = col; g.fillStyle = col; g.lineCap = 'round';
    for (var i = 0; i <= 28; i++) { var u = i / 28, x = bx + (cx - bx) * (u * u * .75 + u * .25), y = by - H * u + Math.sin(u * 3.1) * H * .012, w = H * .052 * (1 - u * .45) * (i % 2 ? 1 : .84); if (prev) { g.lineWidth = w; g.beginPath(); g.moveTo(prev[0], prev[1]); g.lineTo(x, y); g.stroke(); } prev = [x, y]; }
    for (var c = 0; c < 4; c++) { g.beginPath(); g.arc(cx + (c - 1.5) * H * .024, cy + H * .025 + (c % 2) * H * .014, H * .019, 0, TAU); g.fill(); }
    fr.forEach(function (f) {
      var gust = wind * Math.sin(t * 1.3 + f.ph), a = f.a + gust * .07 + wind * .03, L = H * .58 * f.l;
      var ex = cx + Math.cos(a) * L, ey = cy + Math.sin(a) * L * .5 + L * f.droop + gust * L * .06, mx = cx + Math.cos(a) * L * .55 + gust * L * .04, my = cy + Math.sin(a) * L * .32 - L * .14;
      g.lineWidth = Math.max(1, H * .011); g.beginPath(); g.moveTo(cx, cy); g.quadraticCurveTo(mx, my, ex, ey); g.stroke();
      for (var k = 1; k <= nl; k++) {
        var u = k / nl, u1 = 1 - u, px = u1 * u1 * cx + 2 * u1 * u * mx + u * u * ex, py = u1 * u1 * cy + 2 * u1 * u * my + u * u * ey;
        var tx = 2 * u1 * (mx - cx) + 2 * u * (ex - mx), ty = 2 * u1 * (my - cy) + 2 * u * (ey - my), ta = Math.atan2(ty, tx);
        var ll = L * (.11 + .13 * Math.sin(u * Math.PI)) * (.85 + .15 * Math.sin(k * 3.1 + f.k * 9)), flut = Math.sin(t * 6 + k * .7 + f.ph) * .07 * wind;
        for (var sd = -1; sd <= 1; sd += 2) { var ang = ta + sd * (1.2 + u * .3) + flut, lx = px + Math.cos(ang) * ll, ly = py + Math.sin(ang) * ll + ll * .4 * (u + .2); g.beginPath(); g.moveTo(px, py); g.lineTo(px + Math.cos(ang + .6) * ll * .12, py + Math.sin(ang + .6) * ll * .12); g.lineTo(lx, ly); g.lineTo(px + Math.cos(ang - .6) * ll * .12, py + Math.sin(ang - .6) * ll * .12); g.closePath(); g.fill(); }
      }
    });
  }
  // ---- a dromedary walking left: body, one hump, a long neck, legs with knees, a rider or not ----
  function drawCamel(g, x, y, s, step, col, rider) {
    g.fillStyle = col; g.strokeStyle = col; g.lineCap = 'round'; g.lineJoin = 'round';
    g.beginPath(); g.moveTo(x - s * .52, y - s * .58); g.quadraticCurveTo(x - s * .3, y - s * .72, x - s * .1, y - s * .78); g.quadraticCurveTo(x + s * .05, y - s * 1.12, x + s * .28, y - s * .8); g.quadraticCurveTo(x + s * .5, y - s * .66, x + s * .52, y - s * .5); g.quadraticCurveTo(x + s * .5, y - s * .36, x + s * .34, y - s * .34); g.lineTo(x - s * .42, y - s * .36); g.quadraticCurveTo(x - s * .58, y - s * .42, x - s * .52, y - s * .58); g.closePath(); g.fill();
    g.lineWidth = s * .15; g.beginPath(); g.moveTo(x - s * .48, y - s * .58); g.quadraticCurveTo(x - s * .82, y - s * .66, x - s * .9, y - s * 1.14); g.stroke();
    g.beginPath(); g.ellipse(x - s * .96, y - s * 1.2, s * .16, s * .085, -.25, 0, TAU); g.fill(); g.beginPath(); g.moveTo(x - s * 1.04, y - s * 1.26); g.lineTo(x - s * 1.2, y - s * 1.17); g.lineTo(x - s * 1.04, y - s * 1.14); g.closePath(); g.fill();
    g.lineWidth = s * .065; [[-.36, 0], [-.24, Math.PI], [.22, Math.PI], [.38, 0]].forEach(function (l) { var sw = Math.sin(step + l[1]), kx = x + l[0] * s + sw * s * .07, fx = kx + sw * s * .1; g.beginPath(); g.moveTo(x + l[0] * s, y - s * .4); g.lineTo(kx, y - s * .2); g.lineTo(fx, y); g.stroke(); });
    g.lineWidth = s * .035; g.beginPath(); g.moveTo(x + s * .5, y - s * .52); g.quadraticCurveTo(x + s * .62, y - s * .46, x + s * .58, y - s * .28); g.stroke();
    if (rider) { g.beginPath(); g.moveTo(x - s * .06, y - s * .9); g.lineTo(x + s * .12, y - s * .92); g.lineTo(x + s * .1, y - s * 1.26); g.lineTo(x - s * .04, y - s * 1.26); g.closePath(); g.fill(); g.beginPath(); g.arc(x + s * .03, y - s * 1.35, s * .085, 0, TAU); g.fill(); }
  }

  // ================= what Studio offers =================
  var LIST = [
    ['silk', 'Soie', 'La Lettre'], ['garden', 'Jardin fleuri', 'Le Jardin'], ['orchard', 'Verger en fleurs', 'Le Jardin'],
    ['sky', 'Ciel du soir', 'La Nuit'], ['savanna', 'Savane sous la lune', 'La Nuit'], ['loom', 'Métier à tisser', 'Le Pagne'],
    ['weave', 'Bandes tissées', 'Le Pagne'], ['blobs', 'Formes douces', 'Le Magazine'], ['velvet', 'Velours', 'Le Blason'],
    ['party', 'Confettis', 'Le Carnet'], ['sahel', 'Sahel', 'Sahel'], ['ocean', 'Océan', 'L’Océan'], ['lotus', 'Étang aux lotus', 'Le Lotus'],
    ['forest', 'Forêt', 'La Forêt'], ['sakura', 'Cerisiers', 'Les Cerisiers'], ['sunflowers', 'Tournesols', 'Les Tournesols'],
    ['lanterns', 'Lanternes', 'Les Lanternes'], ['roses', 'Roseraie', 'La Roseraie'], ['desert', 'Désert', 'Le Désert'],
    ['champagne', 'Champagne', 'Champagne'], ['butterflies', 'Papillons', 'Les Papillons'], ['globe', 'Village sous la neige', 'Boule à neige'],
    ['snowfall', 'Neige', 'Boule à neige'], ['fireworks', 'Feux d’artifice', 'Feux d’artifice'], ['aurora', 'Aurore boréale', 'L’Aurore'],
    ['lx-savane', 'Savane d’or', 'Premium'], ['lx-lotus', 'Étang de lotus', 'Premium'], ['lx-foret', 'Forêt enchantée', 'Premium'],
    ['lx-cerisiers', 'Paravent de cerisiers', 'Premium'], ['lx-tournesols', 'Champ d’or', 'Premium'], ['lx-lanternes', 'Nuit des lanternes', 'Premium'],
    ['lx-roseraie', 'Velours & roses', 'Premium'], ['lx-dunes', 'Caravane des dunes', 'Premium'], ['lx-rivage', 'Carte du rivage', 'Premium'],
    ['lx-champagne', 'Champagne Gatsby', 'Premium'], ['lx-herbier', 'Herbier aux papillons', 'Premium'], ['lx-givre', 'Fenêtre givrée', 'Premium'],
    ['lx-feux', 'Grand soir', 'Premium'], ['lx-aurore', 'Boréale', 'Premium']
  ].map(function (x) { return { id: x[0], name: x[1], from: x[2], premium: x[0].indexOf('lx-') === 0 }; });

  function palOf(p) {
    p = p || {};
    var o = { bg: hex(p.bg || '#f6f1e9'), ink: hex(p.ink || '#2e2620'), accent: hex(p.accent || '#b98d48'), soft: hex(p.soft || '#e9dcc6'), deep: hex(p.deep || '#2e2620') };
    o.white = [252, 249, 244]; o.black = [8, 7, 6]; o.red = [179, 48, 42]; o.green = [44, 110, 73];
    return o;
  }
  function canvasIn(el, cls) {
    var cv = document.createElement('canvas');
    cv.className = cls; cv.setAttribute('aria-hidden', 'true');
    cv.style.cssText = 'position:absolute;left:0;top:0;width:100%;height:100%;display:block;pointer-events:none';
    el.appendChild(cv);
    return cv;
  }
  // How far the element has travelled through the screen: 0 as it comes in at the bottom, 1 as it leaves at the top.
  function travel(el) { var r = el.getBoundingClientRect(), vh = innerHeight || 1; return clamp((vh - r.top) / (vh + r.height)); }
  function pageTravel() { var vh = innerHeight || 1; return scrollY / Math.max(1, document.documentElement.scrollHeight - vh); }
  function watch(el, s) {
    if (!('IntersectionObserver' in window)) return null;
    var io = new IntersectionObserver(function (es) { es.forEach(function (e) { s.vis = e.isIntersecting; }); }, { rootMargin: '120px' });
    io.observe(el);
    return io;
  }

  function mount2d(el, id, P) {
    var make = SCN[id]; if (!make) return null;
    var cv = canvasIn(el, 'ms-cv'), s = { cv: cv, g: cv.getContext('2d'), fixed: false, vis: true, rev: false }, raf = 0, dead = false;
    function size() {
      var r = el.getBoundingClientRect(), dpr = Math.min(1.5, window.devicePixelRatio || 1);
      s.w = Math.max(1, r.width); s.h = Math.max(1, r.height);
      cv.width = Math.round(s.w * dpr); cv.height = Math.round(s.h * dpr);
      s.g.setTransform(dpr, 0, 0, dpr, 0, 0); s.dpr = dpr;
    }
    size();
    try { s.fn = make(s, P); } catch (e) { cv.remove(); return null; }
    var io = watch(el, s), t0 = performance.now(), ro = null;
    if ('ResizeObserver' in window) { ro = new ResizeObserver(function () { size(); }); ro.observe(el); } else window.addEventListener('resize', size);
    (function loop(now) {
      if (dead) return;
      if (s.vis) { try { s.fn(s.g, s.w, s.h, RM ? 2 : (now - t0) / 1000, travel(el), pageTravel()); } catch (e) { /* a frame lost, the next one draws */ } }
      if (!RM) raf = requestAnimationFrame(loop);
    })(t0 + (RM ? 2000 : 0));
    return { stop: function () { dead = true; cancelAnimationFrame(raf); if (io) io.disconnect(); if (ro) ro.disconnect(); else window.removeEventListener('resize', size); cv.remove(); }, canvases: [cv] };
  }

  function mountGL(el, key, P) {
    if (!LXSH[key]) return null;
    var cv = canvasIn(el, 'ms-gl'), fx = canvasIn(el, 'ms-fx');
    var gl = null;
    try { gl = cv.getContext('webgl', { antialias: false, alpha: false, depth: false, stencil: false, preserveDrawingBuffer: false, powerPreference: 'high-performance' }) || cv.getContext('experimental-webgl'); } catch (e) { gl = null; }
    var G = { raf: 0, scale: .62, dpr: Math.min(1.5, window.devicePixelRatio || 1), avg: 16, lastY: scrollY, vel: 0, vis: true }, ok = !!gl, dead = false, U = {};
    if (ok) {
      try {
        var sh = function (t, src) { var o = gl.createShader(t); gl.shaderSource(o, src); gl.compileShader(o); if (!gl.getShaderParameter(o, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(o)); return o; };
        var pr = gl.createProgram();
        gl.attachShader(pr, sh(gl.VERTEX_SHADER, 'attribute vec2 p;varying vec2 v;void main(){v=p*.5+.5;gl_Position=vec4(p,0.,1.);}'));
        gl.attachShader(pr, sh(gl.FRAGMENT_SHADER, LX_PRE + '\n' + LXSH[key] + LX_MAIN));
        gl.linkProgram(pr);
        if (!gl.getProgramParameter(pr, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(pr));
        gl.useProgram(pr);
        var buf = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, buf); gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
        var lp = gl.getAttribLocation(pr, 'p'); gl.enableVertexAttribArray(lp); gl.vertexAttribPointer(lp, 2, gl.FLOAT, false, 0, 0);
        ['uR', 'uT', 'uP', 'uV', 'uA', 'uD', 'uB'].forEach(function (k) { U[k] = gl.getUniformLocation(pr, k); });
        gl.uniform3f(U.uA, P.accent[0] / 255, P.accent[1] / 255, P.accent[2] / 255);
        gl.uniform3f(U.uD, P.deep[0] / 255, P.deep[1] / 255, P.deep[2] / 255);
        gl.uniform3f(U.uB, P.bg[0] / 255, P.bg[1] / 255, P.bg[2] / 255);
      } catch (e) { ok = false; }
    }
    // no graphics chip: the card's own colours, deepening downwards, under the hand-drawn foreground
    if (!ok) { cv.remove(); el.style.background = 'linear-gradient(180deg,' + rgb(P.bg) + ',' + rgb(mix(P.bg, P.deep, .6)) + ')'; }
    function size() {
      var r = el.getBoundingClientRect(), w = Math.max(1, Math.round(r.width * G.dpr * G.scale)), h = Math.max(1, Math.round(r.height * G.dpr * G.scale));
      if (ok && (cv.width !== w || cv.height !== h)) { cv.width = w; cv.height = h; gl.viewport(0, 0, w, h); }
      var fw = Math.max(1, Math.round(r.width * G.dpr)), fh = Math.max(1, Math.round(r.height * G.dpr));
      if (fx.width !== fw || fx.height !== fh) { fx.width = fw; fx.height = fh; }
    }
    size();
    var fxd = null;
    try { fxd = LXFX[key] ? LXFX[key]({ w: fx.width, h: fx.height, dpr: G.dpr, pal: P, el: fx }) : null; } catch (e) { fxd = null; }
    var io = watch(el, G), ro = null;
    if ('ResizeObserver' in window) { ro = new ResizeObserver(function () { size(); }); ro.observe(el); } else window.addEventListener('resize', size);
    var t0 = performance.now(), last = t0;
    (function frame(now) {
      if (dead) return;
      var dt = now - last; last = now;
      if (G.vis) {
        G.avg += (dt - G.avg) * .08;
        if (G.avg > 27 && G.scale > .34) { G.scale *= .88; size(); G.avg = 18; } else if (G.avg < 13 && G.scale < .8) { G.scale *= 1.04; size(); }
        var t = (now - t0) / 1000, gp = travel(el);
        var dy = scrollY - G.lastY; G.lastY = scrollY; G.vel += (clamp(dy / 40, -1, 1) - G.vel) * .1;
        if (ok) { gl.uniform2f(U.uR, cv.width, cv.height); gl.uniform1f(U.uT, RM ? 3 : t); gl.uniform1f(U.uP, gp); gl.uniform1f(U.uV, G.vel); gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4); }
        if (fxd) { try { fxd.draw(fx.getContext('2d'), fx.width, fx.height, RM ? 3 : t, gp, G.dpr, G.vel); } catch (e) { /* the next frame */ } }
      }
      if (!RM) G.raf = requestAnimationFrame(frame);
    })(t0);
    return {
      stop: function () {
        dead = true; cancelAnimationFrame(G.raf); if (io) io.disconnect(); if (ro) ro.disconnect(); else window.removeEventListener('resize', size);
        if (fxd && fxd.stop) { try { fxd.stop(); } catch (e) { /* gone */ } }
        if (gl) { var lose = gl.getExtension('WEBGL_lose_context'); if (lose) lose.loseContext(); }
        cv.remove(); fx.remove();
      },
      canvases: ok ? [cv, fx] : [fx], gl: ok
    };
  }

  function mount(el, id, pal) {
    if (!el || !id) return null;
    var P = palOf(pal);
    var c = String(id).indexOf('lx-') === 0 ? mountGL(el, String(id).slice(3), P) : mount2d(el, String(id), P);
    if (c) el.setAttribute('data-scene-on', id);
    return c;
  }
  window.MaraScenes = {
    list: LIST,
    has: function (id) { id = String(id || ''); return id.indexOf('lx-') === 0 ? !!LXSH[id.slice(3)] : !!SCN[id]; },
    mount: mount
  };
})();
