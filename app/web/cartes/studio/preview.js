// Marakaj Studio — the card's own picture for the street (177).
// The first screen of the card exactly as a guest sees it — its design,
// its words, its photo, its living picture — drawn in the organiser's
// browser and sent as the card's preview: the street shows it until the
// organiser chooses another picture. Drawn after each save, and once when
// Studio opens a card that has none. Silent: a failure leaves the street
// as it was (the card's photo, else its kind's picture).
//
// The guests' page is opened in a frame the size of a phone (« vitrine=1 »:
// not counted as an opening), then drawn by html-to-image (MIT, vendored:
// vendor/html-to-image.LICENSE).
(function () {
  'use strict';
  var S = window.Studio = window.Studio || {};
  var W = 412, H = 732, busy = false, again = null;

  function shoot(ctx) {
    return new Promise(function (ok, fail) {
      var f = document.createElement('iframe');
      f.setAttribute('aria-hidden', 'true'); f.tabIndex = -1; f.title = 'Aperçu';
      f.style.cssText = 'position:fixed;left:0;top:0;width:' + W + 'px;height:' + H + 'px;border:0;opacity:0;z-index:-1;pointer-events:none';
      var done = false, end = function (err, blob) {
        if (done) return; done = true;
        setTimeout(function () { if (f.parentNode) f.parentNode.removeChild(f); }, 0);
        if (err) fail(err); else ok(blob);
      };
      var timer = setTimeout(function () { end(new Error('trop long')); }, 60000);
      f.onload = function () {
        var w = f.contentWindow, d = w && w.document;
        if (!d || !d.body) { clearTimeout(timer); end(new Error('pas de page')); return; }
        // the blocks' entrance and the scene grown (five seconds)
        setTimeout(function () {
          try { Array.prototype.forEach.call(d.querySelectorAll('.st-b'), function (b) { b.classList.add('in'); }); } catch (e) {}
          try {
            var hide = d.createElement('style');
            hide.textContent = 'html,body{scrollbar-width:none;overflow:hidden}::-webkit-scrollbar{display:none}';
            d.head.appendChild(hide);
          } catch (e) {}
          var s = d.createElement('script');
          s.src = '/cartes/studio/vendor/html-to-image.js';
          s.onerror = function () { clearTimeout(timer); end(new Error('outil absent')); };
          s.onload = function () {
            var fonts = d.fonts && d.fonts.ready ? d.fonts.ready : Promise.resolve();
            fonts.then(function () { return fontCss(d); }).then(function (css) {
              var bg = w.getComputedStyle(d.body).backgroundColor || '#ffffff';
              return w.htmlToImage.toBlob(d.body, { width: W, height: H, pixelRatio: 2, backgroundColor: bg, type: 'image/jpeg', quality: 0.86, fontEmbedCSS: css || '' });
            }).then(function (blob) { clearTimeout(timer); end(blob ? null : new Error('vide'), blob); },
              function (e) { clearTimeout(timer); end(e || new Error('dessin')); });
          };
          d.head.appendChild(s);
        }, 5000);
      };
      f.src = '/e/' + encodeURIComponent(ctx.slug) + '?vitrine=1' + (ctx.preview ? '&apercu=' + encodeURIComponent(ctx.preview) : '') + '&t=' + Date.now();
      document.body.appendChild(f);
    });
  }

  // The card's fonts, only the Latin ones (accents included): Google's
  // stylesheets list every alphabet, dozens of files the card never uses.
  var LATIN = /U\+0000-00FF|U\+0100-02BA|U\+0100-024F/i;
  function dataUrl(url) {
    return fetch(url).then(function (r) { if (!r.ok) throw new Error('police'); return r.blob(); }).then(function (b) {
      return new Promise(function (ok, no) { var fr = new FileReader(); fr.onload = function () { ok(fr.result); }; fr.onerror = no; fr.readAsDataURL(b); });
    });
  }
  function fontCss(d) {
    var links = Array.prototype.map.call(d.querySelectorAll('link[rel="stylesheet"][href*="fonts.googleapis.com"]'), function (l) { return l.href; });
    return Promise.all(links.map(function (href) {
      return fetch(href).then(function (r) { return r.ok ? r.text() : ''; }, function () { return ''; });
    })).then(function (sheets) {
      var faces = [];
      sheets.join('\n').replace(/@font-face\s*{[^}]*}/g, function (f) { if (LATIN.test(f) || !/unicode-range/i.test(f)) faces.push(f); return f; });
      return Promise.all(faces.map(function (f) {
        var m = /url\(([^)]+)\)/.exec(f);
        if (!m) return Promise.resolve('');
        var url = m[1].replace(/^['"]|['"]$/g, '');
        return dataUrl(url).then(function (u) { return f.replace(m[0], 'url(' + u + ')'); }, function () { return ''; });
      }));
    }).then(function (list) { return list.join('\n'); });
  }

  function send(ctx, blob) {
    return fetch(ctx.uploads + '/v1/events/' + encodeURIComponent(ctx.slug) + '/preview?modifier=' + encodeURIComponent(ctx.edit), {
      method: 'POST', headers: { 'Content-Type': 'image/jpeg' }, body: blob
    }).then(function (r) { if (!r.ok) throw new Error('refusé ' + r.status); return r.json(); });
  }

  // The card's picture, drawn and sent; one at a time, the last asked wins.
  S.cardPicture = function (ctx) {
    if (!ctx || !ctx.slug || !ctx.edit || !ctx.uploads || !window.Promise || !window.fetch) return Promise.resolve(null);
    if (busy) { again = ctx; return Promise.resolve(null); }
    busy = true;
    return shoot(ctx).then(function (blob) { return send(ctx, blob); }).then(function (r) { return r && r.key || null; }, function () { return null; })
      .then(function (key) {
        busy = false;
        if (again) { var next = again; again = null; return S.cardPicture(next); }
        return key;
      });
  };
})();
