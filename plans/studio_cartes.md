# Marakaj Studio — the card editor people actually want

The owner (after a user's complaints): « She's trying to modify the card but she's
not able to: can't add text, can't delete all the text, you remove the time and
the box is still there, can't add your own pictures, not enough colours. I need
this to be like Canva. A real dashboard. Something epic, leave nothing behind. »

This plan says what exists, why it blocks her, what Studio is, how it is built
and in what order. Every phase is its own PR, applied live and tested on a phone
before merging (CLAUDE.md).

## 1. What a card is today, and why she is stuck

| Today | Consequence for the person editing |
|---|---|
| 50 designs: 15 classic cards, each a hand-written HTML page under `/cartes`, and 35 animated designs (21 free, 14 Premium) drawn by one 3 800-line page under `/evenements`. | A design is a fixed layout. The number of texts, photos and sections is the model's, not hers. |
| Editing = the card page itself with `?modifier=<token>`: every text node becomes `contenteditable` (the dotted boxes), a photo slot can be replaced and dragged to reframe. | She can only rewrite words inside boxes that already exist. Nothing can be added. |
| The programme is a grid (time · title · detail). Emptying the time leaves the cell. | « You remove the time and it's still there. » |
| Colours: 9 palettes on classic cards, 4 per animated layout. Fonts: 6 pairings. | « Not enough colours », no custom colour, no size, no alignment, no background. |
| Photos: the model's slots only; 36 stock photos; no illustrations or stickers. | « Not enough combination of pictures. » |
| RSVP can be switched off from the app, but the pass/QR block is always drawn under the answer section, even when answers are closed. | A fiançailles card shows « Les réponses sont fermées » and a QR nobody asked for. (A bug to fix now, whatever else we do.) |
| No undo, no versions, no structure view, no share image, no preview image on WhatsApp beyond the title. | Fear of breaking the card; no way back. |
| Server: `events.content` is a flat bag of `t:<key>`, `p:<key>`, `type`, `pal`, `font`, checked key by key (60 KB, 4 000 chars a text, pictures must be the event's own). | Sound and safe, but it can only describe « words written over a model ». |

The honest conclusion: the editor is good at one thing (write over a pretty model)
and cannot grow into what she asks, because the card is not a *document*; it is
a page with holes. Studio makes the card a document.

## 2. The target

Studio = **a document** (what the card contains) + **one renderer** (how any
document is drawn, with every current design as a starting point) + **an editor**
(phone first, desktop too) + **a dashboard** (what the card does: views, answers,
photos, tickets).

### 2.1 The card becomes a document (content v2)

```json
{ "v": 2,
  "theme": { "colors": {"back":"#0f6b4f","paper":"#fbf5e8","ink":"#1f2a23","line":"#e3d3b0","accent":"#c2185b","onAccent":"#fbf5e8"},
             "fonts": {"display":"Yeseva One","body":"Mulish","script":"Great Vibes"},
             "motif": {"id":"wax-emerald","density":2}, "motion": "doux", "corners": "soft" },
  "blocks": [
    { "id":"b1","type":"cover","variant":"framed","props":{"kicker":"Cérémonie de dot","names":"Salimata & Boukary","sub":"unissent leurs familles","photo":{"key":"…","pos":[50,40],"zoom":1.1}} },
    { "id":"b2","type":"families","props":{"left":"Ouédraogo de Tanghin","right":"Sawadogo de Kaya"} },
    { "id":"b3","type":"programme","variant":"timeline","props":{"title":"Le déroulement","items":[{"time":null,"title":"Accueil","detail":"Les familles se saluent"}]} },
    { "id":"b4","type":"text","props":{"title":"Un mot des deux familles","body":"…","sign":"Les familles …"},"style":{"bg":"accent","align":"center","size":"L"} }
  ] }
```

Block types at launch (every one can be added, removed, duplicated, hidden,
reordered; each has 2–6 layout variants):

couverture · texte libre (titre, corps, signature) · photo · galerie (2–8 photos:
grille, mosaïque, carrousel, polaroïds, arches) · familles · programme (horaires
facultatifs) · infos pratiques (lieu + itinéraire, tenue, parking, contacts) ·
compte à rebours · lieu (carte) · ajouter au calendrier · contribution / cagnotte
(Orange Money, Wave, Moov, banque, avec « copier » et objectif facultatif) ·
citation / verset · RSVP · billets (161) · album des invités (155/164) ·
carte d'invité / QR (158, **off by default**) · vidéo (lien YouTube) · musique ·
ornement / séparateur · pied de page · bloc libre (texte + photo + bouton).

Each block has a style layer: fond (couleur du thème, couleur libre, dégradé,
motif, photo avec voile, scène animée), marges S/M/L, alignement, taille des
textes, police du bloc (sinon celle du thème), coins, ombre.

The theme: 6 colour roles from **40 presets or any colour** (picker + « prendre la
couleur dans ma photo »), **12 font pairings or mix your own** from 30 fonts
(self-hosted, OFL), motifs (wax ×8, bogolan, Faso Dan Fani, géométrique, pois,
floraux ×12, textures papier), motion (aucune · douce · vivante: entrées, pétales,
étoiles, lucioles, confettis, poussière d'or).

### 2.2 One renderer, every design kept

A single runtime draws any v2 document. The 50 current designs do not disappear:
each becomes a **starting document + theme + decor pack** (Dot = wax bands +
emerald/fuchsia/gold + families block + programme + …). Choosing « Dot » gives
the same card as today, then everything in it is editable. The animated scenes
(silk, garden, sky, savanna, loom, weave, blobs, moonface, and the 14 luxe
compositions) become **scene backgrounds** a block can take — the cover first.

Converter: a v1 card (template key + `t:`/`p:`/`pal`/`font`) is turned into a
v2 document the first time its organiser opens Studio; guests keep seeing the v1
rendering until she saves. No card changes under anyone's feet.

Why blocks and not a free canvas: Canva is a fixed-size canvas; an invitation is a
web page read on hundreds of phone sizes. Free positioning everywhere breaks on
the next phone. Studio is structured below the fold and **free inside the
cover** (stickers and text placed by percentage on the cover photo) and on the
poster (§2.5), which is where free placement is wanted.

### 2.3 The editor (phone first)

Where: `marakaj.com/studio/<slug>?modifier=<token>` — opened from the app's
« Modifier la carte » as today (in-app browser), and a real URL on a computer.

Layout on a phone: the live card, full width; a bottom bar **Blocs · Style ·
Photos · Texte · Aperçu**.
- Tap a block → it is selected (outline) and its sheet opens: fields, variants,
  style, « Masquer », « Dupliquer », « Supprimer ». Drag the handle to reorder.
  « + » between two blocks opens the block library.
- Tap a text → write in place (kept from today). Floating toolbar: taille S/M/L/XL
  · gras · italique · MAJUSCULES · alignement · couleur (thème ou libre) · police ·
  lettres espacées. Enter adds a line; an emptied field collapses (no dotted
  ghost); the field's « × » removes it where the block allows.
- Tap a photo → Remplacer (appareil · galerie du téléphone · banque Marakaj · mes
  photos) · Recadrer (pinch to zoom, drag) · Filtre (aucun, noir et blanc, sépia,
  chaud, doux) · Cadre (aucun, cercle, arche, polaroïd, wax) · Légende.
- Style tab: the theme (colours, fonts, motif, motion) with live preview and
  « Couleurs depuis ma photo ».
- Undo / redo (document history in memory), autosave of the draft on the phone,
  « Enregistrer » to the server, **versions** (the last 20 saves, « Restaurer »),
  « Voir comme un invité », « Partager » (WhatsApp with the poster image, copier le lien).

Desktop: the same editor with the sheet as a right-hand panel. This is the
« real dashboard » on a computer.

### 2.4 The library

- Photos: 36 → 200+ CC0 photos, tagged (mariage, dot, baptême, naissance, diplôme,
  gala, hommage, nature, textures, Ouaga/Afrique de l'Ouest), searchable. « Mes
  photos »: every picture the business ever uploaded, reusable across its cards.
  Limits: 40 photos per card free, 150 Pro; 4 MB each, stored as WebP 1600 px;
  the guests' album stays separate (164).
- Illustrations (SVG, tinted by the theme): 150+ at launch — florals, rings,
  colas, calebasses, djembé, balafon, baobab, cauris, symboles adinkra, colombes,
  bougies, toques, rubans, confettis, cœurs, étoiles, cadres, arches, coins,
  séparateurs.
- Motifs: wax ×8, bogolan, Faso Dan Fani, kente-like, géométriques, pois, floraux,
  papiers.
- Fonts: 30 (display / body / script), self-hosted.
- Music: 20 royalty-free tracks (we already have cleared sources) + own upload
  (Pro); plays on tap (browsers refuse autoplay).

### 2.5 The « epic » helpers

- **Affiche**: one tap makes a 1080×1920 and a 1080×1080 image of the card
  (names, date, cover photo, theme) for WhatsApp status and sharing — and it
  becomes the card's preview image (og:image) so a shared link shows the couple,
  not a grey box. Server-side too (Satori + resvg on the Worker) so every card
  has a preview even before it is edited.
- **Imprimer**: A5/A6 PDF of the poster (Pro).
- **QR de la carte** for printed invitations.
- **Couleurs depuis ma photo**: 3 themes proposed from the cover photo.
- **Phrases prêtes**: by kind of event — mot des familles, versets, étapes du
  programme, tenue, remerciements — French first; Mooré/Dioula later if asked.
- **Assistant d'écriture (Pro)**: « Écris le mot des familles en trois lignes,
  ton chaleureux » — a Worker calling Claude; never writes without a tap.
- **Vérifier ma carte**: contrast too low, date missing, text too long, photo
  too small, RSVP without closing date.

### 2.6 The guests' side

- RSVP: names of the +1s, a note, « du côté de », **1–3 custom questions**, a
  closing date; when closed, the form **and** the QR disappear unless passes are
  on. Defaults by kind: fiançailles/dot → RSVP off, QR off, album off.
- Pass / QR as its own block, off unless « entrée contrôlée » is on (158).
- Share buttons, add to calendar (kept), itinerary (kept), contribution with
  « copier » (kept, now a block), countdown (kept), album (kept), tickets (kept).
- Views per card, answers, shares per day → the dashboard in the app.

### 2.7 Server and data

- Migration 170 — content v2: `events.content_v2 jsonb`, `events.content_version
  smallint`, `event_content_save_v2(slug, edit, doc)` with a validator written in
  plpgsql: block type whitelist, field types and lengths per type, ≤ 40 blocks,
  ≤ 8 photos per gallery, texts ≤ 4 000 chars, colours as `#rrggbb`, fonts and
  scenes from whitelists, total ≤ 200 KB; pictures must be the event's own or the
  business's library (below). `event_public` returns v2 when present.
- Migration 171 — versions: `event_content_versions` (20 kept per card, author,
  time, size), `event_content_restore(slug, edit, version_id)`.
- Migration 172 — business library: `business_pictures` under `events/<org>/library/…`
  (the uploads Worker's event route, as 154), reusable across the business's cards;
  the stock photos indexed in `card_stock` (key, tags, author, licence).
- Migration 173 — RSVP questions and closing date; the per-kind defaults.
- Migration 174 — views and shares counters (`event_views`, written by the Worker,
  summed by day), read by the dashboard.
- Worker: `/studio/<slug>` serves the editor app; `/e/<slug>` renders v2 or v1;
  `/e/<slug>/affiche.png` the poster (Satori + resvg-wasm, cached a day,
  invalidated on save); `og:image` on every card.
- Renderer and editor: plain JS modules under `app/web/studio/` (no framework,
  like the current pages), < 150 KB gzipped for the renderer, lazy scenes, WebP
  with srcset, self-hosted fonts.
- Flutter: « Modifier la carte » opens Studio; new « Tableau de bord » tab on a
  card: vues, réponses, photos, partages, billets; « Dupliquer la carte »;
  nothing else moves.

### 2.8 Free and Pro

Free: every block, custom colours, 12 font pairings, stock photos and
illustrations, 40 photos a card, poster image, 5 versions.
Pro (as today's Pro doors, « Marakaj Pro : … »): premium scenes and decor packs
(157), music upload, writing assistant, PDF print, 20 versions, analytics history,
album (164), tickets (161), passes.

### 2.9 Phases — each a PR, applied live, tested on a phone, then merged

**Phase 0 — what she needs this week (3–4 days)**, in the current editor, no
new data model:
1. The pass/QR block hidden when RSVP is off or answers are closed; « Carte
   d'invité (QR) » as an explicit switch in the app, off by default for
   fiançailles/dot.
2. Programme: « + étape » and « − » on each step; an emptied time collapses its
   cell (no dotted ghost); « Masquer les horaires » on the whole programme.
3. « Masquer cette section » on programme, mot, photos, infos, album, pied de page.
4. « Bon à savoir »: add/remove an item.
5. Colours: 24 more palettes and three free colours (fond, encre, accent) with a
   picker, saved as `pal: {back, ink, accent}`.
6. Text size S/M/L on any text (saved as `s:<key>`).
These are the complaints in her screenshots, answered without waiting for Studio.

**Phase 1 — the document and Studio MVP (3–4 weeks)**: migrations 170–171, the
renderer, the converter and starting documents for the 15 classic designs, the
editor (blocks add/remove/reorder/hide/duplicate, text styles, theme editor with
custom colours and fonts, photo blocks with crop/filter/frame, stock library,
undo/redo, autosave, versions, guest preview, share). Classic cards move to v2 on
first edit.

**Phase 2 — the animated world and the library (3 weeks)**: the 35 animated
designs as starting documents with scene backgrounds and decor packs; motifs,
illustrations/stickers (free placement on the cover), music, poster/og image,
share images, views counter and the dashboard in the app (174).

**Phase 3 — the helpers and the guests (2–3 weeks)**: colours from photo, phrases
library, writing assistant (Pro), PDF print, RSVP questions and closing date
(173), business photo library (172), desktop polish, « Vérifier ma carte ».

About 9–11 weeks in all, 10–14 PRs. Risk to name: the animated page is 3 800
lines of bespoke drawing; Phase 2 may keep some luxe compositions as « fixed
layout, editable content » for a while rather than block them all at once.

### 2.10 What I need from you

- A yes on Phase 0 (I can start it right after this message).
- The name (« Studio »?), and the Free/Pro split above.
- Two or three real cards (with their owners' permission) to test the converter;
  your sister as beta tester — her screenshots were exact.
- The live approval of each migration as the PRs arrive (our standing rule).
