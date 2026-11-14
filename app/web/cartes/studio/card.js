// Marakaj Studio — the guests' page (171): the card's document, drawn.
(function () {
  'use strict';
  var B = window.CARTE || {}, S = window.Studio, root = document.getElementById('card');
  var doc = B.doc;
  if (!doc || typeof doc !== 'object' || !Array.isArray(doc.blocks)) {
    root.innerHTML = '<p style="color:#fff;padding:32px 20px;text-align:center;font-family:system-ui,sans-serif">Cette carte n’est pas disponible pour le moment.</p>';
    return;
  }
  var ctx = {
    slug: B.slug, title: B.title || '', kind: B.kind, card: B.card, date: B.date, time: B.time, place: B.place || '',
    rsvp_on: B.rsvp_on !== false, album_on: B.album_on !== false, tickets: B.tickets === true, preview: B.preview || null, presence: B.presence || null,
    api: B.api || {}, uploads: B.uploads || null, editing: false, demo: B.demo === true
  };
  S.mount(root, doc, ctx);
  // the phone's bar in the card's own colour
  try {
    var m = document.createElement('meta'); m.name = 'theme-color'; m.content = S.colorsOf(doc.theme).back;
    document.head.appendChild(m);
    document.body.style.background = S.colorsOf(doc.theme).back;
  } catch (e) { /* the default bar */ }
})();
