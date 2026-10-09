# Mara (formerly Kaj) — Build Plan

Every task below is written to be pasted directly into Claude Code, in order.
Each milestone ends with something demonstrable.

---

## Where things stand

**Done and tested**

| Piece | Status |
|---|---|
| orgs → entities → departments | schema built |
| Invitations by short code, no email required (M2) | built, tested — 585-line suite |
| Platform admin flag + create_org (006) | built, tested — no screen yet |
| Admin screens: org settings, entities/departments, people, invites | built (M2) |
| Expense entry alongside contributions | built |
| Public web build on Cloudflare, redeploys on push to main | live |
| Codespace serve.sh — local dev serving with real credentials | built |
| 8 scoped roles (owner…employee, observer, approver) | built |
| Double-entry ledger, hidden behind plain-language actions | built, tested |
| Offline outbox + idempotent sync | built, tested |
| Undo by reversal (append-only history) | built, tested |
| 22 RLS policies, cross-tenant isolation | built, proven by test |
| Church contributions + expenses | built |
| Flutter app running on web and Android | built |
| Login by email/password, org resolution, profile routing (M1) | built, tested offline |
| Offline session + device PIN | built, tested |
| Admin screens: people, roles, structure, settings (M2) | built |
| Invitations by short code or QR | built, 15 assertions |
| Report screens: weekly summary, balances, giving, close-the-day (M3) | built |
| Visibility ('summary' vs 'full') actually enforced | built, proven by test |
| Account creation — sign up by phone or email, then join with a code | built, tested |
| Free-text entry names, notes and characteristics | built, tested |
| Accounting: journal, résultat, bilan, grand livre, balance | built, 16 assertions |
| Editable chart of accounts, transfers between cash accounts | built |
| Activity log + super admin console (logs, data, device) | built, 10 assertions |
| Ignace's farm: stock, flocks, eggs, invoices (M4) | built, 17 assertions |
| Esperance's store: products, sales, returns, expiry alerts (M5) | built, 11 assertions |
| Employees, shifts and payroll (M5) | built, 8 assertions |
| Camera capture with zero required fields, R2 upload (M5) | built, 10 assertions |
| Barcode scanning and on-device OCR (M5) | built, 22 assertions, unproven on a device |
| A photographed delivery note becoming stock (M5) | built, 17 + 5 assertions |
| Serial numbers and a product's photographs (M5) | built, 2 assertions |
| Renaming, archiving and deleting a business | built, 25 assertions |
| Employee sign-up: profile, then a code from their manager | built, 17 assertions |
| Manager sign-up: apply, be approved, own the business | built, in the same suite |
| Staff records for every business, volunteers included | built, 17 assertions |
| A farm with livestock and crops, not only poultry | built, 11 assertions |
| Invoicing for every business, not only the farm — numbered, cancellable, shareable as an image | built, 14 assertions |
| Phone numbers with a country code picker, stored as E.164 | built, 12 assertions |
| A colour per business profile, measured against WCAG rather than eyeballed | built, 14 assertions |
| Platform console: search, filter and page across thousands of businesses | built, 8 assertions |
| A business chooses its own colours, previewed before saving | built, 13 + 13 assertions |
| Every screen is a real page: back, refresh and bookmarks all work | built, 12 assertions |
| Languages: French and English live, per device; Mooré and Dioula scaffolded for a translator | built, 11 assertions — entry path + every home screen, hubs and admin tiles. The switcher offers only French and English (`enabledLocales`); the two draft locales stay hidden until a speaker reviews them. Honest gap: the screens built since (vitrine, orders, courier) are French-only — an English device reads them in French. See M12. |
| Accessibility: every street tile is one labelled button to a screen reader, the basket stepper is two named 40 px buttons, photos carry alt text, every icon button has a tooltip, and "reduce motion" on the device stills every entrance | built, 8 assertions |
| The credit book (M8): sales à crédit, repayments, qui-me-doit-combien | built, 11 assertions |
| Tontines (M13): members, rounds, whose turn, close-the-round contract | built, 8 assertions |
| Production (transformation): ingredients become a product, cost moves with them, one unit's cost computed | built, 9 assertions |
| Product lifecycle: rename without rewriting receipts; owner-only archive that keeps all history | built, 6 assertions |
| Scale to 200 articles: search in Articles, searchable recency-ordered ingredient picker, "Refaire" on past runs, ingredient flag off the sale sheet | built |
| Crédit as a payment method: a credit sale moves stock and snapshots cost like cash, money lands in créances, the carnet debt links to the sale | built, 8 assertions |
| Notifications phase 1: in-app bell, per-recipient rows, five trigger events, employees quiet by design | built, 9 assertions |
| Ajout multiple: twenty articles in one save, one line each, parsed with per-line errors before anything is written | built |
| The handwriting reader: a photographed carnet page becomes editable product lines via AI vision, dormant until ANTHROPIC_API_KEY is set on the Worker | built |
| The glass restyle: aurora wash behind every page in the business's own palette, frosted surfaces, soft geometry — no blur, so it runs on cheap phones | built |
| Team access (M-rights): the owner's dial per tool per tier — hidden/view/edit, server-enforced on prices, credit and production | built, 8 assertions |
| Security hardening (032): closed a full-audit finding list — the critical one let any sign-up set is_platform_admin on their own row (RLS gates rows, not columns); locked by a column-scoped grant AND a guard trigger that survives a Supabase re-grant, plus membership checks added to the definer functions (receive_products, pay_employee, record_shift, record_return) that wrote where the caller's RLS would have refused | built, 10 assertions |
| The plan flag (065, M10 block 1): Free or Pro per business with a paid-until date, set only by the platform, effective plan decided in one place (a lapsed Pro reads Free and nothing else moves), carried on `my_orgs()` and the cached org list, a Formule card on the business settings, a Kaj Pro tile and filter on the console, the change in the activity log | built, 5 SQL tests + 8 Flutter tests |
| The gates (066, M10 block 2): the Free/Pro line in `platform_settings`; `feature_access()` answers `view` on a Pro tool for a Free business, after the dial and never below it; payroll, tontines, the dial and the currency rates held server-side; caps on staff, invoices a month and photos as BEFORE INSERT triggers; every refusal starts "Kaj Pro :" and the app opens the door to pay; a Pro badge on Analyses, Comptabilité, Tontines and Accès de l'équipe; one paywall sheet with the price, the platform's Wave number and "J'ai payé"; a Kaj Pro console page listing the requests and setting the number and prices. Honest gap: the read-only Pro tools (analytics, the accounting hub) are held in the app, not by the database — an owner calling those functions by hand reads their own figures | built, 8 SQL tests + Flutter tests |
| The delivery cut (067, M10 block 4): `delivery_share_pct` in `platform_settings` (10 to start); `orders.platform_fee` fixed with the fee by a trigger, whole francs, none on a pickup, none on orders placed before 067; a new percentage changes the next order and never one already placed; the courier's tally shows fees, share and net; `platform_delivery_settlement(month)` says what each courier owes; a Règlement des livreurs console page with the month stepper, the total due and the rate. The share is a debt settled by Wave until M9 lets the platform hold the money | built, 4 SQL tests + Flutter tests |
| A lean Android build that updates itself: one APK per processor and R8 shrinking (about half the weight), every push to `main` published as a GitHub release with a fixed *latest* link, `BUILD_SHA` in every build and `version.json` beside the web app, and a banner in the app — "Télécharger" on a phone, "Recharger" in a stale tab — when the two differ. Alerts on a closed Android app still need FCM, a Firebase project this build does not have | built, 8 Flutter tests |
| Vitrine personnalisée for Kaj Pro (068): a cover photograph over the band, a tagline, opening hours, the buttons' colour, up to six pinned articles at the top of the shelf and a switch to leave out-of-stock off — one validated JSON on the business, written through `set_storefront_style()` behind the plan, shown by `storefront()` only while the business is Pro (a lapsed Pro keeps its words; the street goes back to the common design), the cover servable through the same photo gate as the articles. Set from the business settings under the vitrine, with the Pro badge and door for a Free business | built, 4 SQL tests + Flutter tests |
| Words, not pictures (October audit): one labelled bar at the foot of the shop, farm and association home screens — the home screen, three everyday tools and **Plus** for the rest by name, a labelled rail on a wide screen — replacing up to eight bare icons in the top bar; the order-alerts switch became a one-time card | built, Flutter tests |
| A delivery has a reach (069): `delivery_max_km` (15 to start) or the shop's own (1–200 km); beyond it no fee is quoted, `delivery_check()` tells the basket the distance, the reach and "too far", and a trigger refuses the order at the door. The audit's 1 149 450 FCFA quote for 7 660 km is gone | built, SQL + Flutter tests |
| The dial locks, not only hides (069): Factures (triggers on invoices and payments), Photos (a document needs 'edit', an article's photo the Articles dial, the gallery 'not hidden') and Rapports (the eight report functions) refuse a member the owner shut out. Each report and gallery function is guarded by renaming it `<name>_core` and fronting it with a thin check — bodies untouched, bundle re-runnable; strangers still get empty answers | built, 10 SQL checks |
| An open app keeps up: `SessionController.refresh()` re-reads businesses, role, plan and dial on resume and every five minutes — a Pro upgrade, a new dial or a removal reaches a phone that never restarted; silent offline, no rebuild when nothing changed | built, 6 Flutter tests |
| The audit's smaller fixes: the association screen takes the dial; the courier page re-checks while waiting for approval and on the board; the till asks before selling an article below zero (never nagging a shop that does not count stock); server refusals in the basket said in the server's words; a dialog-controller disposal crash in three dialogs (OwnedController) | built, Flutter tests |
| A vitrine that sells (070, audit package 2): articles published unless hidden (ingredients never) and **Tout publier** for the ones waiting; an open window with an empty shelf left off the directory; an article with no photo shows its name on a wash of the shop's colour instead of a grey box; a tap opens the article (photo, words, stock, stepper, a WhatsApp question naming it) and a round « + » adds without opening; grid cells measured, not guessed — no band of white under each row; the header says kind · address · retrait/livraison; directory cards show three of the shop's articles (photos as a mosaic, else a menu board) instead of its initial; a vitrine meter with the next step on the settings and the shop's home | built, 5 SQL tests + Flutter tests |
| List first, map on demand (audit package 3): the street opens on its shops under a compact band, and « Voir la carte » opens a full-screen map with a strip of shop cards (goods, Voir la vitrine, Itinéraire); pins closer than a thumb share a numbered bubble that zooms in; the settings show the shop's pin on a small map before saving, a tap moves it, and a franc CFA pin outside West/Central Africa is said in red (both open shops were in New Jersey) | built, 7 Flutter tests |
| Spots for sale — « Mettre en avant » (071, audit package 4): an owner buys an article's place at the head of À la une, or the whole shop's at the top of the list, for 7 or 30 days at the platform's prices (1 000 / 3 000 F an article, 2 500 / 8 000 F the shop); an article needs a photo, a price and stock; paid by Wave, « J'ai payé », validated in the console; at most 8 article spots at once, the next queued behind the earliest end; Kaj Pro includes one free 7-day article spot a month; the street marks paid places « Sponsorisé »; a counter (seen in the strip, windows and articles opened, added to a basket, ordered) and each spot's figures over its own days | built, 6 SQL tests + 5 Flutter tests |
| The console opens on today (072, audit package 5): « À traiter » — applications, Kaj Pro and spot payments to check, couriers to approve, orders stuck (pending 2 h, on the road 3 h) — each counted and opening its screen; « Ce mois » — Pro, spots, the delivery cut and what the windows sold; « Croissance » — businesses, stocked windows, orders against last week, new shoppers, windows visited; « Santé » — silent 30 days, empty windows, pins far from their currency, articles without a photo; the nine unlabelled app-bar icons become named « Outils »; « Écrire aux boutiques » reaches every business's admins through the bell | built, 3 SQL tests + 4 Flutter tests |
| A delivery that runs itself (073, audit package 6): every status a dated event; the shopper's order card is a live timeline (each step's time, the courier's name and a call button once on the road, the shop's number) with the four-digit **handover code** the courier must enter to close the delivery; « Échec » with its reason (absent, injoignable, refusée) cancels and tells everyone; the shop's orders say how long each has waited and flag the stuck ones (pending 30 min, ready with no courier 20 min, on the road 2 h) with « Je livre moi-même » (no platform share); the cash a courier collected is owed to the shop until it taps « Reçu »; a shop names its own couriers, who get its orders alone for 10 minutes; the board is sorted nearest shop first | built, 7 SQL tests + 4 Flutter tests |
| Foundations (074, audit package 7): **the till works with no signal** — a cash or credit sale that cannot reach the server is kept in the phone's outbox with its client uuid and sent by the sync loop, the home says « N ventes en attente d'envoi »; **live orders** — Supabase Realtime pushes the shop's and the shopper's order changes to their screens (074 adds `orders` to the publication; row security filters); **migrations by CI** — `scripts/apply-migrations.sh` applies what the live database has not had, one transaction each, recorded in `kaj_migrations` (seeded live), run by *Apply migrations* once `SUPABASE_DB_URL` is set; **the public pages opened in a browser** on every web build (fixtures, phone size, the shopper's words must be there); a directory card now says what the shop sells to a screen reader; the owner's steps for Sentry, the Play Store and Firebase written down | built, Flutter tests + browser check |
| Settings folded: the business settings open on an index — Identité, Paiements, Vitrine, Livraison, Position, Équipe et accès, and for the platform Formule et modération — each row saying where that part stands (« Wave non configuré », « Tarifs de la plateforme · 15 km », a red « Loin de la zone de la monnaie »), each part its own page with its own Enregistrer; on a desk (≥ 840 px) the index stays on the left. Compte opens on a profile card, then titled cards (Mon compte, the business, Outils, Plateforme, Aide, À propos) and « Se déconnecter » alone at the bottom | built, Flutter tests |
| Sécurité (075): the device code becomes a lock — asked again after 1, **5** (default), 15 or 60 min away, or never — with fingerprint unlock on Android; « Cacher les montants » hides the day's total until touched; the password change asks the current one; the account's sessions listed (« Android · Chrome · Cet appareil ») with « Déconnecter cet appareil » and « Déconnecter les autres appareils »; a new device rings the account's bell; the account's security history; an owner's « Sécurité de l'équipe » sets the longest lock any member may choose (strictest rule across businesses wins), and « Déconnecter partout » closes a lost phone's member's sessions (never an owner's) | built, 5 SQL tests + 6 Flutter tests |
| Wave checkout (076 + `workers/pay`): orders, Kaj Pro and spots paid by Wave or by card on Wave's page through Kaj's aggregator account; the amount fixed by the database for what is the caller's to pay; the signed webhook settles once (Pro and spots activate themselves); the shop's share sent to its own Wave number by Payout API, idempotent, failed payouts retried and shown in Console › Paiements Wave; the platform's switches (Wave, card, share %); dormant until `WAVE_API_KEY` / `WAVE_WEBHOOK_SECRET` / `PAY_URL` and the platform's switch | built, 6 SQL + 7 Worker + 5 Flutter tests |
| Two-step sign-in for platform admins (077, optional since 078 — off by default, switched on in Compte › Sécurité › Plateforme, switching off needs the code): Supabase Auth's authenticator-app factor (TOTP) for the platform admin; `two_step_gate()`, PostgREST's pre-request hook, refuses an admin token below aal2 on every table and function, their own shops included, except `my_two_step()` — one gate in front of the 53 functions and 3 policies that read `is_platform_admin`; the app stops the resolve at « Validation en deux étapes » — enrol (QR, a button that opens the app on the phone, the key to type) or the code once per sign-in; the activation in the account's security history. Realtime and Storage are outside the hook, and nothing behind them reads the flag | built, 5 SQL tests + 8 Flutter tests |
| Google sign-in: « Continuer avec Google » above the e-mail form, for sign-in and sign-up, drawn only when the project has Google on (`/auth/v1/settings`); the web redirects to Google and back to `/connexion`, Android goes through the browser and back on `bf.kaj.app://login-callback`; the session that returns is taken only if this device noted it left for Google (15 min), never twice, and lands on the device code exactly as a password does. Needs the owner's Google OAuth client in the Supabase dashboard (README › Google sign-in) | built, 10 Flutter tests |
| Articles as a list or as cards (079): a switch in the Articles bar, remembered on the device; every article carries its picture in both — a thumbnail on the row, a square on the card — fetched with the caller's token; `product_photo_keys(org)` answers the whole shop's newest non-PDF photo per article in one call (invoker, documents' own policy); an article with none shows its initial; slivers, so only the articles on screen are built and fetched | built, 2 SQL tests + 3 Flutter tests |
| « POWERED BY » over the owner's logo — the K and « KAJ CONSULTING » (no « LLC », the owner's word), on a white rounded card (`assets/brand/kaj_logo.png`, kaj-consulting.com), as on the owner's example — at the foot of every street page (vitrines, the directory, Mes commandes), in place of the old wordmark and tagline; « Toutes les vitrines » kept | built, 1 Flutter test |
| The owner's logo everywhere the app shows itself: KAJ Consulting's K is the browser tab icon, the installed web app's icons (plain and maskable), the Android launcher icon at every density and the shared link's picture; `KajMark` (`assets/brand/kaj_mark.png`) opens the sign-in, the splash (over a progress hairline) and the code screen, in place of a wallet icon, a bare spinner and a padlock | built, 2 Flutter tests |
| The street, deeper into the goods sites' way (allbirds.com, the owner's reference): a thin ink strip over the header taking turns with three true lines; a centred header that slides away scrolling down and back on the first move up (never at the top); every section label and every tile rising as it scrolls into view (ScrollReveal), a row's tiles a beat apart; the product photograph leaning in slowly under the pointer inside its frame (ZoomOnHover) while the tile holds still; the « + » sliding up under the pointer on a desk, always there on a phone; the basket and an article opening as a drawer from the right on a desk, from the bottom on a phone; the footer link drawing its underline; the hero bands and the sign-in settling in. All of it still under « less motion » | built, 7 Flutter tests |
| The business side, the street's way: every card on every inside screen (75 of them, through `KajCard`, which is Card with its parameters passed straight through) and every panel of the shop's home rise into place as they scroll into view; section titles already small letter-spaced capitals; under « less motion » they are simply there | built, 2 Flutter tests |
| Delivery and Kaj's online payment are Kaj Pro (081): a Free shop quotes no delivery, its window says it does not deliver (style.delivers, every plan) so the basket offers pickup only, and a delivery order is refused at the orders table itself; Kaj's Wave checkout is not ready for a Free shop and a payment for its order is refused at wave_payments (a shop's own Wave link stays free); 'delivery' and 'online_payment' join the Pro list. Two ways to price a run: « Prix au km » (base + per km from the door) or « Minimum, puis au km » — the minimum covers every door up to N km, each km beyond adds the per-km price (orgs.delivery_included_km, platform default 0); Paramètres › Livraison chooses, and tells a Free shop that delivery is Kaj Pro | built, 4 SQL tests + 6 Flutter tests |
| The « Pro » strip and Kaj and Kaj Pro side by side: a slim strip with a small black « PRO » pill over every page inside a business that is not on Kaj Pro, for its owner and admins only (ProStrip, drawn once in the router's _withOrg); it opens `/o/<id>/kaj-pro` — month or year (« 2 mois offerts » when the year costs less), Pro's price on its column, then « Pour tous », « Avec Kaj Pro » (the platform's own Pro list, so the page says what the database enforces) and « Sans limite » row by row, and at the foot how to pay (Wave, the number, « J'ai payé »). Every badged tool and Compte open the same page | built, 3 Flutter tests + the paywall's 4 moved to it |
| The footer's signature: « POWERED BY KAJ », KAJ in bold — words only (the logo and its white card gone) | built, footer test updated |
| The basket never under the footer: it floats over the goods while the shopper browses, and once the end of the page comes into view it stops in the page — « VOTRE PANIER », each article's photo and name, the total, « Commander » — above « Toutes les vitrines » and the centred footer (the floating card steps aside; measured after each scrolled frame) | built, 2 Flutter tests |
| The weekly competition (086): leagues by kind (shops, farms), city (set, or the nearest Burkina town to the pin within 40 km) and size (orders and till sales in 30 days: under 30, under 150, beyond); the score is the week's earning, never the wallet — spending never costs a place, prizes and expiries are not in it. « Classement » (from Mes cauris): an animated podium of the top 3, your place and the cauris to the place above, last week's result, « Le dire sur WhatsApp » for the podium, a switch to hide the name from others (« une boutique de … ») and one for the messages. Four times a week (Mon, Wed, Fri, Sun 19:00) every business that earned hears its league's top 3 and its gap — never the bottom of the board; each Monday the top 3 of every league win 100/60/30 cauris, the winner a free 7-day spot, all three the « Top 3 de la semaine » badge on their vitrine. Scheduled by pg_cron. Pro subscribers race too | built, 5 SQL tests + 4 Flutter tests |
| Académie Mara (087): lessons of two minutes for each kind of business — guides (welcome, cauris, the league) and missions (first article, open the vitrine, three photos, first sale, the farm log, first vitrine order). Each plays as steps on a drawn phone with a hand that travels to the button and taps it (still under reduced motion), a caption in a few words, « Essayer maintenant » to the very page. A guide is done once seen; a mission only when the business's own data says it happened (checked on the server) — then it glows « Mission réussie » to collect. Each lesson pays the business 10 cauris once, whoever of its people takes it; each person climbs their own level (Apprenti, Commerçant, Maître). Associations learn but earn nothing. Opened from Compte, Mes cauris, the Plus menu, and « ? » on Articles, Commandes and Bandes. No voice-over yet: no recorded audio, and no Mooré/Dioula speech synthesis to lean on | built, 4 SQL tests + 4 Flutter tests — remplacée par Le Chemin (097) |
| The association's trust level (088), instead of points: an association does not race and earns no cauris. Its level is read off its own books on the server — Vérifiée par Mara (a platform admin's tick, set from the association's trust page), money recorded in 6 of the last 8 weeks, 80 % of the last 90 days' expenses with their receipt, corrections under 1 in 10, six months on Mara. Nouvelle, Régulière, Fiable, and Exemplaire only once verified. A card on the association's home opens the five pillars, each saying where it stands and what to do. It opens nothing yet: the fundraising vitrine and Wave collection it is meant to unlock wait on the platform's fundraising decisions | built, 4 SQL tests + 3 Flutter tests |
| Tools are earned (089), for everyone, and the database holds the door: no trial days, no business kept open for being here first. Shops and farms: Factures at 70 % of vitrine, Production at 90 %, the credit book after 3 finished orders, a second business with Mara Pro only. Locked means nothing new — the server refuses a new invoice, production run, debt or application with the reason — but what was kept stays readable (« Voir (lecture seule) ») and a debt is still repaid. Pro opens the three tools. The home's path card draws the four tools as pictures, open or with their goal; the lock sheet shows the tool, the goal, a bar and the way there. Associations are not on the path | built, 7 SQL tests + Flutter tests |
| Cash for now, Mara Pro by card only (090): every business is cash-only until a platform admin ticks « Autoriser Wave » for it (Paramètres › Plateforme). Until then a vitrine order paid by Wave is refused by the server, the vitrine never shows the Wave number, Wave checkout is closed, and the app hides the Wave settings (« Espèces pour le moment ») and the till's Wave button. Mara Pro is paid through Stripe only — the manual « J'ai payé » and the Wave number to Mara are gone; until the card is open the Pro page says « Bientôt disponible ». Phone numbers are checked for length per country (8 digits for Burkina, 10 for Côte d'Ivoire and the US…) on sign-up, the profile, invitations and invoices: « 8 chiffres pour Burkina Faso (+226) » | built, 2 SQL tests + Flutter tests |
| The guided first setup, and the Académie in pictures (091): a new shop or farm is walked through four steps before its home opens — its name; its first article (name, price, stock, with the three lit up one after the other), put on the vitrine; the vitrine (open, one phrase, the customers' phone checked for length, the quartier); its position (« Utiliser ma position » on a map, or « Plus tard », which earns no cauris) — then « C'est prêt ! ». Each step is a big picture and one short line; the store cannot open without an article (finish_setup() checks). Businesses already stocked or with an open vitrine are marked done. Only admins see it; employees go straight in. Settings: free essentials first (Identité, Vitrine, Position, Paiements, Sécurité), Livraison and Équipe et accès apart under MARA PRO; each saved page offers « Suivant : … »; « Mettre en avant » and the Pro dressing folded under « Vitrine avancée »; the vitrine meter drawn as a ring and six pictures, not a list of choices; no « Pro » strip over the setup or the settings. Académie: lessons as picture tiles, the level as three medals, and the lesson phone draws the very button the hand taps (« Accepter », « + », « Vente ») | built, 2 SQL tests + Flutter tests |
| English on the screens, first pass: `context.tr('French…')` with the French as the key and lib/core/l10n/en.dart as the English (1,239 phrases — every Text, label, hint, tooltip, title, error line and SnackBar of the screens, the Académie's lessons and the server's lesson titles, the settings sections, the path and vitrine pictures, the trust pillars); `{name}` placeholders for the numbers; a phrase with no English reads in French, never as a key. The language is the person's choice in Compte › Langue (French or English); changing it rebuilds every page at once. A test fails when a wrapped phrase has no English. Still French: the legal pages (to be translated by a person, not drafted), country names, and lines composed in code from several pieces | built, 3 Flutter tests |
| French first, English on a switch; deeper English; settings tidied (092): the app opens in French whatever the phone, and Compte › Préférences has an « English » switch; Compte's groups fold. Second translation pass — ternaries, state lines, section labels, the server's refusals (1,480 phrases). The « PRO » strip: the pill on the left without its star, the Mara seal in the middle. Livraison and Équipe et accès are drawn locked under the seal (with their cauris price) unless Pro or unlocked; Production and the credit book in Compte go through the earned-path lock. A vitrine is public only with 8 items on sale — the owner still sees it and is told « X / 8 »; the vitrine's first step is 8 items. Sponsoring pays by itself as the 3rd order of the sponsored business is finished, and « Mes cauris » says « +200 cauris par entreprise parrainée » with each sponsored business and how far it is. Académie: the phone is drawn as Mara's own screen (status bar, app bar, card, rows, bottom bar) and the steps follow one another by themselves, with pause | built, 3 SQL tests + Flutter tests |
| marakaj.com: the site's own domain. The Android app, the vitrine links a shop shares, the update check and the link-preview image point to https://marakaj.com (`core/site/site.dart`, `SITE_URL` overrides); the Workers accept it as an origin, and Stripe/push links come back to it. The domain is a Custom Domain of the `dbms` Worker, attached in the dashboard; dbms.kabore-boss.workers.dev keeps working | built |
| Every vitrine dresses itself; Pro arranges it (093): « Habiller ma vitrine » under Vitrine avancée, with a live phone preview. For every plan: a cover from the shop's own photos, one of six colours, a tagline, and opening days and hours (chips and times, written as « Lun–Sam 8h–19h »). With Mara Pro or its cauris unlock: the shelf's layout (grille, grandes photos, liste, menu), up to six articles à la une, out-of-stock hidden, any colour, and the « Ouvert maintenant / Fermé » banner the server reads from the schedule in Ouagadougou's time. A lapsed Pro keeps its arrangement and the street shows the basics. `vitrine_free_basics` (1) opens the basics; 0 is 068's rule | built, 1 SQL test + Flutter tests |
| Vitrines d'exemple (094): seven platform shops on the street — Rowan Bike Shop, Tony Pizza, Chinese Fu Restaurant, Jersey Bakery, Bob Electronics, Ghana Restaurant, Thomas University Restaurant — 10 to 15 articles each, photos shipped with the web app under /showcase/ (cut from the owner's bike and dish pictures and the p-tit-paris photos). Pro, dressed (093), no pin: never on the map, « Pas à proximité » on the page and the directory tile, listed after the real shops. Commander explains and stops before any sign-in; a BEFORE INSERT trigger refuses any order; they earn no cauris (no league). Console › Vitrines d'exemple: on/off the street, Voir la vitrine, Gérer (the platform admin becomes owner and edits them with the ordinary business screens), Recréer les vitrines manquantes (showcase_seed, never touches an existing store) | built, 1 SQL test + Flutter tests |
| The street showed two shops of seven: a tile listened only to the nearest scrollable, a shrink-wrapped grid that never scrolls, so every tile below the first screen stayed invisible (ScrollReveal now listens to every scrollable around it, and measures after the frame). Vitrines d'exemple with the most photos first (095: showcase_slugs ordered by photographed articles), and inside one the photographed articles first | built, SQL + Flutter tests |
| A smaller footer on every street page: the Mara mark and « Au Service du Peuple » on one line, « POWERED BY KAJ · © year Mara » on the next (about 65 px instead of 240) | built |
| Speed and a lighter app. Web: the business half (till, books, farm, console — 61 screens) is a deferred library (core/nav/business_screens.dart) fetched the first time somebody opens a business, so a shopper's first download is 4.7 MB of code instead of 6.3 (1,126 KB instead of 1,464 KB brotli). Measured again with the files compressed ahead of time (the first measurement counted the test server's own compression): the first shop shows in 18.5 s instead of 20.2 s at 1.5 Mbit/s and 300 ms, 2.0 s on a fast line either way — what remains is Flutter's engine and framework. The splash seal is inside index.html so it paints with the page, and after 8 s it says « Connexion lente — Mara arrive… »; the local database opens while Supabase starts. Everywhere: the launch questions (two-step, platform admin, invitations) and a business's opening (plan terms, feature states, team dial) are asked at once, one round trip instead of three. Android: text recognition and the barcode model come from Google Play services (were 12.5 + 6 MB inside the APK), native libraries compressed, Dart symbols split out (kept as a CI artifact), the AAB carries arm and arm64 only. Measured: arm64 APK 50.7 → 15.3 MB, 32-bit APK 42.8 → 15.1 MB, AAB 105 → 54.6 MB | built |
| Offline on request: the first time a business's home opens on a device, its admin is asked « Utiliser Mara sans connexion ? »; « Oui » shows « Télécharger pour hors ligne », which prepares in ticked steps — on the web the whole app (since 108 kept by web/mara_sw.js — both halves and every asset, carried into each new build; offline_sw.js is gone), the chart of accounts, and a farm's stock and flocks. Compte › Préférences › Hors ligne prepares again. Shoppers are never asked; since 108 every visitor's browser keeps the part of the app its visits used (below). Proven in Chromium: precached, network cut, server stopped, the app boots from its copy | built, Flutter tests |
| The neutral brand kit (docs/brand/mara-neutre, merged from brand/mara-neutre): no red, no blue. App colours — maraDeep #4A3122 for grounds (splash, setup, the street's announcement bar), caramel #C49A6C for what shines on it, blanc cassé #F4F2EE, noir #0E0D0C ink, a warm grey for secondary type; the vitrine's ink, stone and lines likewise. Profile defaults in the kit: a shop Mara brown, a farm caramel, an association graphite (businesses that chose a colour keep it). The seal, wordmarks and stacked logo in app/assets/brand, the web icons, favicon, link preview and inline splash, the Android launcher and adaptive icons and launch screen, all from the kit's brown set | built |
| Settings that say where they stand, and the bell when a tool opens (096): « Paramètres de l'activité » shows « N sur 4 terminés » and a tick or « À faire » on each first step; « Vos articles » comes first — on sale against the minimum, photos, the four gestures that add an article, « Ajouter un article » and « Tout publier »; Paiements is hidden while the shop is cash only (rates moved to Identité); the vitrine asks for its phone and address (before, only the invoice header could, and invoices open at 70 %); « Vitrine avancée » keeps the preview and the free basics, the Pro part is one locked card; « Mettre en avant » folded on its own. The path card opens a guide to 100 % (each step lit in turn, « Faire maintenant » opening its rubrique) and leaves the home at 100 %. org_unlocks + check_unlocks() ring the admins (notify_org_admins, so push) once per step when invoices, production or the credit book open, triggered by articles, photos, the vitrine's words, phone, address, pin and orders; what was open before 096 is recorded as seen; the home shows the celebration once (unseen_unlocks / mark_unlocks_seen). Grounds turn graphite #3B3A38 with brown and caramel accents: splash, icons, Android launcher from the kit's gris set; the shop default ink graphite, farm caramel, association black | built |
| Le Chemin (097): one path in place of the path card, the vitrine guide, the vitrine checklist meter, the Académie and Mes cauris — four stages, Ouvrir, Remplir, Vendre, Grandir, and 15 steps for a shop or a farm (farm words and checks: « produits », the farm log instead of the till): first article, vitrine open, phone and address; the vitrine minimum of articles, three in photo, a sentence, the pin, a first sale (a farm: a first log line); a first accepted order, three finished, a customer back, the till (or the log) kept 7 days; a first tool bought with cauris, a business sponsored, the week's top 3 (only in a week its league was a race). The server is the single truth (path_steps, org_path_done, path_progress / path_goal / path_sync): a step reached stays reached and is paid its reward once, 5 to 20 cauris, into the ledger as 'path_step' — by 096's triggers and new ones on sales, the farm log, cauris unlocks, sponsoring and the podium, so nobody has to open the app; what every business had reached when 097 shipped was recorded unpaid, once (path_seeded). The gates become step-based, computed live: invoices after `articles` and `photos`, production after stage 2, credits after three finished orders, a second business with Pro; Pro and other profiles never locked; path_gates_open (the owner's switch) opens them all, path_league_min (3) is how many must earn in a league this week before the board says more than « Bientôt ». path_state() is what the app draws (stage, steps with remembered and live counts, tools, the wallet for admins, league_open). The home has one card — the next step, its picture, why, how far, what it pays and opens, « Faire maintenant »; the screen « Mon chemin » (route chemin) has the wallet, the stages, the tools, what the cauris buy, the referral code and « Détails » with the rules and the history. Removed: the Académie (its tables, functions and lesson rule dropped; old lesson lines stay as history), the old cauris screen, the vitrine guide sheet, the vitrine checklist meter and the home nudge. No live shop had invoices or production open under the 089 % rule when 097 shipped, so nobody was relocked | built |
| The phone's language, and a vitrine that travels well: with no choice in Compte the app follows the phone (English on an English phone, French otherwise, and it follows a change of the phone's language while open); the Compte switch now reads « Langue du téléphone par défaut ». Every shared vitrine link is https://marakaj.com/s/<slug> whatever address the app was opened at, and the site Worker (workers/kaj-app/src/index.js, now run first) sends the old dbms.kabore-boss.workers.dev name to marakaj.com for good and writes each /s/<slug> page's own preview — the shop's name and line as title, its blurb, article count and its cover (or first photographed article) as the image — so WhatsApp shows the shop, not Mara. « Partager » opens three ways out: « Mettre en statut WhatsApp » (a 1080 × 1920 picture — the shop's photo, its name and line, four articles with prices, a QR code and marakaj.com/s/<slug> — previewed, then shared as a file so WhatsApp offers « Mon statut »), « Envoyer à un contact » (name, line, the link alone on its line for the preview), « Copier le lien » | built |
| Never an empty home: when the server has no path yet (a database before 097), a shop's or farm's admin sees « Complétez votre activité » opening the settings, whose rubriques say « fait » / « à faire »; a path that did not load for want of signal shows nothing rather than a wrong card. CLAUDE.md: app code that needs a migration is merged only once that migration is live | built |
| Readable without JavaScript, for Google's verification of the sign-in screen (« Mara » and its logo instead of the Supabase address): marakaj.com's own page names Mara, says what it is and links the privacy policy and the terms; the site Worker serves /confidentialite and /conditions as plain pages (workers/kaj-app/src/legal.js), the same words as the app's screens — test/legal_pages_test.dart fails if they drift. The privacy policy now says what a Google sign-in gives Mara (name, e-mail, photo) and what it is used for | built |
| Services in the vitrine, for shops, farms and associations (098): a product can be a service (products.is_service, price_from « à partir de », the 083 unit « / heure »): no stock ever (a trigger keeps it at 0, a check says so; refused as a delivery received, a production run or an ingredient), never « Épuisé », sold at the till without moving stock. Services and articles never share a name (ensure_product p_is_service; renames refused in French), and an article with stock cannot become a service. The vitrine shows a « Services » section with « Réserver »; a services-only basket is « Sur rendez-vous » — pickup, no delivery, « Date et heure souhaitées » required — and reads as a booking everywhere (basket, notice, « Terminée »). One « Mes services » screen for every profile. Associations get a vitrine: public from one service (vitrine_min_items_association), on the street marked « Association », the photo step counted as met, « Ma vitrine et mes services » and « Demandes » on their home; still off Le Chemin, no cauris. A finished order writes nothing in the books (as before for shops: the till records the sale); an association's books are untouched | built |
| Associations, and a bell that says what it is about (099): an association's Compte, settings and photos no longer show a shop's or a farm's tools — no Production, no Livraison, no « Mettre en avant », no carnet page read into stock, no cauris prices on its Pro badges; it keeps comptabilité, tontines, its vitrine, services and « Demandes », its team, and the carnet, whose one button is « Une somme due » (a cotisation, the hall's rent, a loan — no article). A second business needs Mara Pro on a business already owned, whatever its profile (second_business_locked, the 089 door and path_locked); « 2e entreprise » answers for the person reading it, so an employee who owns nothing is not shown a lock; nothing else locks for an association. notifications.params carries each ring's facts (whose it is — shop, customer or courier — the order, the customer, the amount): a tap opens what it is about (the shop's Commandes or the customer's Mes commandes, the article, the customer's carnet page, the tontine, Mon chemin, the league, Mara Pro, the vitrine's spots, the courier's page, Sécurité), and an English phone reads the line in English, built from the facts; the server's French message stays for the push and for older rows. A customer who cancels is heard by the business (« Awa a annulé sa demande »). A customer's pushed order ring opens Mes commandes. Security: notify_org_admins and notify_platform_spot were callable by any signed-in person since 063 (any text to any business's admins, pushed) — now the server's alone | built, 8 SQL tests + 15 Flutter tests |
| The team in one place, a worker earned, photos counted, the platform's gifts (100): for a shop, a farm and an association alike, « Équipe » is the one place for people — who is in, adding somebody (the invitation), replacing or removing them, the invitations out (« en attente » / « ne peut pas entrer : place prise », send again, withdraw) and each person's salary per month, week or day (free; « Paie et journées » pays one period and says « / semaine »; paying stays Pro); Administration › Personnes keeps roles and passwords and points to Équipe to add. The owner plus one worker is free once the first setup is done (an association at once), more is Mara Pro or the team unlocked with cauris, held on the server at every door; a Basic business photographs 10 articles, the 11th needs Pro or a 50-cauris photo slot. Associations spend what Mara gives them; the console gives cauris, promotional cauris spent first and gone on their day, or a Pro tool until a date (« Offert par Mara »), and a gift is never the week's score. The picker filters by kind and names each owner; a switch beside the bell; four tones and the buzz for the app's own ring, now on the farm's and the association's homes too; the vitrine's number opens WhatsApp; a production corrected moves its shelf and its cost price. Security: a delivery note or receipt filed on a published article could be the vitrine's public picture and was served to the street — only pictures are now; an admin could add a trainer's grant (no seat, hidden), invite or insert an owner, or move the owner's row — only the platform names those | built, 17 SQL tests + 25 Flutter tests |
| Stock never below zero, vitrine orders that move it, a farm's analyses, a business asked for without the person (101): products.quantity and the farm's stock_movements refuse, at the point they are written, any decrease below zero — the till, a credit sale, a typed name never received, a production and its correction, a delivery reversed, a farm's feed, a direct write — in French, naming the article and what is left (« Il ne reste que 3 Savon », « Plus de Savon en stock »); an old negative count stays, may rise, never falls; a service is never refused. The till blocks before asking (the « vendre quand même » override is gone); a sale or a sack of feed queued offline that the server refuses is set aside, not retried, and shown on the home with « Compris »; the farm's consumption sheet checks the last known stock. Accepting a vitrine order (shop or farm) takes its articles, recorded in order_stock_moves; refusing takes nothing; cancelling an accepted one by any path gives them back once; services and pre-orders move nothing; place_order refuses « Épuisé » and more than is left, and the vitrine's stepper stops at what is left (storefront_stock), the vitrine saying « Plus que 3 » only when 5 or fewer are left. A vitrine order handed over or delivered is a sale of its own (sales.order_id, once per order): its lines, its money booked as the till books cash or Wave ('Ventes'), the shelf untouched — nobody rings it at the till any more, and the Commandes screen says so; an order accepted before 101 takes its stock then, as far as the shelf goes; a finished order can never be cancelled. This replaces 098's « a finished order writes nothing in the books » for every kind: an association's finished service booking books its income too. Every stock refusal carries SQLSTATE MA001, which the outbox reads first; a refused offline sale offers « Corriger le stock puis refaire la vente ». Analyses for a farm (farm_analytics: this month against the last, what sold best and worst, where the money goes, each flock's losses and laying, the feed; a finished order dated by its finish), locked like a shop's behind the 'analytics' tool — Pro or cauris — and held on the server for both: the five shop analytics functions now refuse without the tool too (platform admins aside). Asking for another business asks only about the business: the server takes the person's name, phone and email from the profile and the account | built, 12 SQL tests + 9 Flutter tests |
| An association's first minutes, Équipe in one place, the domain (102): a new association (and a church) is walked through as a shop is — its name and its kind (tontine, église, groupement, culturelle, sportive, autre, each with its line) and a sentence; its first three members (church_members: a name and a phone, records not accounts, no seat, no Pro; the same phone twice is one member) and/or a WhatsApp message inviting them, skippable; optionally one service on the vitrine, its phone and its area; then « C'est prêt ! » and, on the home, « Encaissez la première cotisation » until money has come in (feature_states.first_income). Finishing sets setup_done_at, which opens the one free worker (100); every association and church already there is marked set up once, so nobody is walked through or loses a worker; feature_states' setup_done now says what the team says (an association created after 091 was told « not set up »). Administration: the people entry opens Équipe, the old « Personnes » screen is gone — its information, profile edit, responsibility (only below the caller, never super administrator), password, sign-out and deletion live in Équipe's person sheet, offered only for somebody the caller outranks, never the owner nor oneself; a salary is shown to the owner and for those the caller outranks; the hub is graphite and caramel, every word translated; the administration pages and Équipe say « Réservé aux administrateurs » to anybody else, the console to the owner or a super administrator; Équipe is on the shop's home too. Every helper text, comment and plan says marakaj.com (a vitrine at marakaj.com/s/<slug>); real login emails at kajapp.com untouched | built, 7 SQL tests + 13 Flutter tests |
| Administration made safe (103), applied live as a hotfix: no client writes orgs, memberships or pending_invitations directly any more (an admin could set plan, suspension, Wave, showcase, photo slots, verified on their own business); super administrator is the platform's to give (never invited, never set by a business), every role change, invitation, removal (revoke_membership) and sign-out only for somebody below the caller, never the owner nor a trainer; manages_user never targets a platform admin, an owner or a trainer (closes the password-reset takeover), and the account Worker refuses platform admins too; claim_my_invitations matches only what auth.users holds as confirmed (profiles.phone no longer proves a number, nor is it writable directly); the console and audit log are the owner's (and a super administrator's), platform people shown as « Mara »; salaries set and seen by the owner or above the person, never one's own; profiles readable by oneself and one's admins, colleagues named through colleague_name(); payout number, Wave handle, kind of business and invoice identity owner-only, the owner notified when changed; the team-access dial the owner's; TRUNCATE revoked everywhere. Deferred: hiding the payout and tax columns from members (1b below) | built, 17 SQL tests, applied live |
| Mara's switchboard (104), the command center's phase 1: a catalog of the tools the platform can show or hide, each with the kinds that have it — Factures, Carnet de crédit (shops, farms, associations), Corrections des ventes et livraisons (shops), Production (shops, farms), Tontines, Paie et journées, Comptabilité (all three), Analyses (shops, farms) — and a switch per kind of business (a legacy church is an association) or per business, « Par défaut » / visible / masqué, until a date if said; a business's switch over its kind's over the catalog, an expired switch none. A tool the business paid for is never hidden: a paid Mara Pro or cauris it spent (Mara's gifts are not payments); hiding it for the business is refused, a kind's switch leaves it be — until the payment ends: then the switch applies and the owner is told once per lapse (« Votre Mara Pro a pris fin : … », feature_pay_watch), « À faire » lists it, renewing brings it back. A rule left from a business's former kind decides nothing and can only be cleared. The device keeps the last hidden list, so an offline start hides the same tools. Every switch is read where the tool is drawn — the homes' bar and Plus, Compte's rows, Équipe's payroll, the owner's dial, Le Chemin's tools and spending, the unlock celebration, the article's « Ingrédient de production » — and at its address, which says « Pas disponible pour votre activité » (OrgAccess.isHidden, folded into the dial's canSee/canEdit; feature_states.hidden); and at the server: a trigger on each tool's tables and 24 entry functions rebuilt with feature_guard refuse a hidden tool in French (MA002) to everyone in the business, Mara's people inside it included; no cauris spent on a hidden tool; an offline action refused for it is set aside, not retried. The platform's journal (platform_actions, paged by moment and id) logs every change with before and after and its undo, run once through a whitelist and never stale; the owner is told of a change to their business. Promises proven: installing changes nothing (P1: a photograph of every member's tools, every business's states and the whole street at 103, identical after 104–107), no dead switch (P2), the platform's alone (P3) | built, 10 SQL tests + P1 before/after + 14 Flutter tests |
| Mara's command center (105), phases 2 and 4's shell: a graphite « Admin » pill with caramel words on the top bar of every business home (beside « Changer d'activité » and the bell), the picker, Compte and the street, drawn only for a platform admin, opens the center; a business opened from the center says « Ouverte depuis le centre admin · Retour au centre admin ». The center: on a computer a rail — À faire · Entreprises · Types d'activité · Demandes · Vitrines et rue · Pro et cauris · Paiements · Personnes · Réglages · Journal — on a phone a bar with À faire, Entreprises, Demandes, Pro et cauris and « Plus »; one search across the top (Ctrl/Cmd+K) for businesses (name, address, phone or the owner's, typed with spaces), people (name, phone, e-mail) and orders (the start of the number, the customer), each opening the fiche, the person or the order. The console's screens are the sections' pages, unchanged and at their own addresses (the old row of tool chips and the « À traiter » list are gone). « À faire » (platform_todo): requests, « J'ai payé » for Pro and for spots, couriers, stuck orders (waiting over 2 hours, on the road over 3), failed Wave payouts, Pro tools a switch hid again when their payment ended, businesses silent 30 days, and what ends within 7 days (a Pro plan, a tool opened, promotional cauris, a spot, a switchboard rule) — each count opens its screen or its businesses (platform_todo_list); refused offline sales are not counted, the server never sees them. Entreprises: one « Associations » filter finding the legacy churches too (search_orgs); tick several, then cauris (or cauris before a date), a tool until a date, a message or an archive for all at once (platform_bulk loops 100's gifts, 072's message, 014's archive): one journal line per business, one refused (a vitrine d'exemple) never stopping the others, each refusal said by name. Réglages: 47 platform settings by group with their names, typed their own way (platform_set_setting: a key that exists, never a marker nor 107's request page, a value of its own type, a whole number from 0 to a billion — a decimal only for the delivery fee and reach and the Wave commission, which every reader takes as numeric —, a percentage never above 100), who changed them last; the two-step switch (078) shown and changed in Sécurité; the Pro console, the Wave console, the couriers' share and the two-step switch write through it too. Journal: every platform change, with « Annuler » where it can be taken back — cauris (never more than is left, refused once spent, the business told), a tool back as it was, an archive restored, a restore undone, a setting unless changed since; a message never. The single gifts and the row archive go through the journal as well. Nothing any shop, farm or association, or any vitrine, shows changes; only the platform passes any of it, on the server. Settings nothing reads since 097 (progress_tools_pct, progress_orders, progress_trial_days) are left out | built, 8 SQL tests + 19 Flutter tests |
| The fiche entreprise (106), the command center's phases 2 and 4 for one business — a shop, a farm or an association alike: Entreprises › a business opens its fiche. Aperçu (platform_org_overview): health and last activity, the plan and its end, cauris and promotional cauris, members, the vitrine open and what is on sale, Mara's own switches and lines, the owner (name, phone, e-mail), and what wants attention (suspended, « J'ai payé » waiting, a spot to decide, Pro, a tool or a switch ending within 7 days, silent, never used, setup unfinished), each one tap from where it is dealt with; « Ouvrir l'activité » goes in as Mara. Identité (platform_update_org_identity): name, kind, address (slug), money, phone, street address, and Mara's verification for an association; the kind only with the business's name typed back, the new kind finding its chart of accounts (additive); one journal line before/after with « Annuler », the owner told « Mara a modifié l'identité de votre activité : … ». Vitrine: the owner's own editor (the settings at their Vitrine part) opened as Mara under « Vous modifiez la vitrine de X en tant que Mara », with the street's vitrine live beside it on a computer. Mara's hand is caught by a trigger on orgs, not wrappers (no function of another migration redefined): a platform admin who is not a member changing a vitrine's columns (open, text, dressing, colours, logo, pin, delivery), the identity's or the plan through any door — the editor, the old console's sheet, set_org_plan, set_org_verified — is logged with its undo; one editing session (same person, part, business, 30 minutes, nothing between, nothing she set changed since by anyone) is one line and one bell; a kind changed through 103's update_org rings 103's bell only; the owner is told for the vitrine and the identity (never for the plan); an owner's or a member's edit is never logged. The undo (platform_undo_org_columns, whitelisted) puts back only what is still as Mara left it, else refuses « Annulation impossible : « … » a été modifié depuis », and tells the owner. Fonctions: 104's board for the business, « Par défaut · Visible · Masquée » until a date with a word, a paid feature locked « Payée — ne peut pas être masquée ». Équipe: the owner's Équipe screen, as Mara. Pro et cauris: the plan until a date (journaled, undoable), the console's own « Offrir » panel (moved out of the gifts screen, not copied), the tools open with their dates, given or paid. Journal: the center's Journal for this business, with « Annuler », beside the business's own log. « Voir comme le commerçant »: the home and Compte drawn with the owner's role, the plan's locks and what the switchboard hides, on a phone's width, scrolling but untouchable (a courtesy: the server still lets the platform write); nothing that opens by itself on a home runs there, and Mara opening a business no longer spends its owner's « débloqué » moment. The owner's bell says what Mara changed, in French and English, and opens it | built, 14 SQL tests + 12 Flutter tests |
| Types of business and the request page (107), the command center's phase 3: « Types d'activité » has a tab per kind (shops, farms, associations — a church is an association). Fonctions: 104's switchboard at the kind's level, the impact said before saving (« Ce changement touche 12 boutique(s) ; 2 ont leur propre réglage ; 1 l'ont payée et la gardent »). Réglages par type: kind_settings holds a kind's own free numbers — free_photo_items, free_max_staff, free_max_invoices_month, vitrine_min_items (shops, farms), vitrine_min_items_association — read through kind_setting(kind, key), the global setting when the kind has none; org_free_workers, org_photo_limit, trg_cap_free_plan, vitrine_min, path_goal and plan_terms (its 'kinds', only when one is set; the paywall reads PlanTerms.forProfile) honour them. Delivery left out: each business sets its own distance. Vitrine par défaut: a kind's layout, colour and cover (none, or the first photographed article), shown only by a vitrine never dressed (storefront_style still '{}'), never a vitrine d'exemple — on Basic only the free options (the colour and the cover, while 093's basics are free), the layout on Vitrine+ (Pro) only; the owner's first dressing takes over. Mise en route: a kind's optional steps off (shops and farms: vitrine, position; associations: members, vitrine), never a required one; setup_steps_off(org) read by both setup screens. The request page (« Page de demande »): platform_settings.application_form — a welcome, the kinds offered, up to 12 questions (texte, choix, nombre, oui-non; help, obligatoire), in order, with a live preview; name, address and kind always asked. apply_for_org gains the answers as an 8-argument signature (101's 7 stays for older builds and meets the same page), kept as asked in org_applications.answers (written through its functions only: no direct insert, update or delete) and shown on the Demandes cards (platform_pending_applications), with ready refusal reasons; the applicant's bell says accepted (the business to open) or refused with the reason, and the journal keeps each decision. Every change the platform's, in the journal with « Annuler » (a stale undo refused). Nothing set is today: test_batch107 computes every number, vitrine and the terms with 107 and with the old definitions put back, and compares | built, 19 SQL tests, app tests |
| The owner's fixes (108), for the shop, the farm and the association: the business's bar stays on every page of the business — the till's Vente/the home's Accueil, Articles, Commandes, Factures, Plus (Stock, Bandes for a farm; Historique, Rapports for an association) — or its rail on a computer, the page's place selected and Plus for a page reached from it; a tap switches tool, the home always underneath, so back returns to it and never leaves the app — the place already selected does nothing, even from deeper in it, and a page holding input not saved (a new invoice or its correction, the settings' rubriques, a photo's articles to confirm) first asks « Quitter sans enregistrer ? »; a page that is none of the places selects none; Plus opens in the business's colours; a deep link lands with its bar; a sheet, a dialog, the camera or a full-screen flow still covers it; no bar while the first setup holds the home (one ShellRoute around `/o/<id>`, the home publishing its places to the frame). « Administration » in Plus for whoever runs the business. « La position de ma boutique » (« de ma ferme », « de mon association ») names the business's place in the setup, the settings and Le Chemin's step (path_steps, 097's text only); the street's « Ma position » stays the shopper's. « Nouvelle vente » says « Choisissez les articles demandés par le client ici » (a farm's carnet: « les produits »). Cauris: a tool that waits says « Disponible avec vos cauris dans 23 jours » and the day, on its button and in Mon chemin's list; the wallet is read again when the sheet opens (a stale copy said « il en manque » to somebody who had enough); a tool on Le Chemin offers Mara Pro complet in cauris; the wait and the price are the platform's (platform_set_cauris_cost, journaled with « Annuler », 085's setter through it), and spend_cauris takes nothing for a tool the kind has not (104's catalog) or a paid Pro already has, 104's hidden-tool refusal kept. The device code is asked only of somebody who belongs to a business — owner, member, trainer — once, the day the first business arrives; a shopper's or a courier's phone is never locked by it (a code set before is kept, unused); a platform admin's phone keeps it, business or not — the console is behind it — after the second step as before, and still locks on a cold start with a stale token (the fact kept on the device until sign-out) | built, 6 SQL tests + P1 before/after, 3 Flutter test files |
| Signing in at the order, a number proved on WhatsApp (109), for a shop's vitrine, a farm's « À vendre » and an association's services alike: a stranger browses the street, every vitrine and every article and fills a basket (kept on the device) without an account; « Commander » or « Réserver » opens a bottom sheet — « Connectez-vous pour commander », « Continuer avec Google » first and big, « Se connecter autrement » and « Créer un compte » at the bottom (the sign-in page opens on account creation for the latter, `/connexion?compte=nouveau`); the vitrine is the way back (kept on the device across Google's reload on the web, `google_return_to`), and back signed in within half an hour the same basket's order opens by itself, once (`street_order_after_sign_in`); « Mes commandes » still asks to sign in. Before the order, when the platform asks (Réglages › Commandes de la rue › « Numéro WhatsApp vérifié avant de commander », `order_phone_verified`, **off as installed** — ordering is then exactly 101's, proven case for case), a shopper with no proved number gives it (Burkina Faso unless chosen, its country's length checked) and types the six digits WhatsApp brought (« Renvoyer » after a minute; refusals said in words); the order sheet then says the proved number instead of the optional field. Supabase makes and checks the code (phone change → verifyOTP phone_change); its « Send SMS » hook posts to the new kaj-whatsapp-otp Worker (`workers/whatsapp-otp`: Standard Webhooks signature, five minutes, the WhatsApp Cloud API's authentication template with the code in its body and copy button, only to an account that already has an e-mail, the code never logged; secrets only in Cloudflare, deploy-whatsapp-otp.yml dormant without them). The server enforces it: place_order (and so every booking) refuses « Vérifiez d'abord votre numéro WhatsApp » before anything is written and records the proved number; order_phone_gate() answers the app, signed in only. Setup below, « Numéros vérifiés par WhatsApp (109) » | built, 5 SQL tests (P1 against 101 put back) + 9 Worker tests (fake Meta) + 21 Flutter tests |
| The vitrine's switches (110), on 104's switchboard — a « Vitrine » group, each switch « Par défaut » as installed (with no rule every vitrine is the same answer for answer: p1_110_before/after photograph the whole street, what each owner reads and every vitrine door, at 109 and after 110): « Commandes en ligne » (shops, farms, associations) — hidden, the vitrine is a showcase: its shelf, « Commandes fermées pour le moment » under the name and in the strip, no « + », no « Réserver », no basket (a kept one is not restored), and every order or booking refused in words by a trigger on orders, whoever writes it; orders already received go on and « Commandes » and Paramètres › Vitrine say so. « Services et réservations » (all three) — the services leave the shelf, the search, the previews, À la une and the photo gate, a booking (alone or in a basket) is refused, no service is created (MA002), « Mes services » is not drawn (store, farm, association homes) and its address says « Pas disponible ». « Livraison » (shops, farms; Pro tool) — pickup only (no « delivers », no quote, no fee), a delivery order refused, the rates and reach kept still (an unchanged save passes; the settings stop sending them), no Livraison part, no cauris spent on it. « Paiement en ligne » (all three; Pro tool) — Wave is off the vitrine and a Wave order or checkout refused, the shop not « ready », Mara's payout number kept, its part not drawn; 090's wave_allowed stays Mara's per-business tick: Wave reaches the vitrine only when both say yes, and the till's own Wave handle is untouched. « Vitrine Plus » (all three; Pro tool) — the free basics only, on the street (storefront, vitrine_default_style, the cover) and in « Habiller ma vitrine » (no Pro part, no Pro door; the Pro part refused at set_storefront_style, the arrangement kept for when it shows again). « Mettre en avant » (all three) — no spot asked for, paid (« J'ai payé » or Wave) or read, the card not drawn, Mara's own pick off « À la une ». « À vendre sur la vitrine » (farms) — the farm's articles leave its vitrine (its services stay) and an order for one is refused; « À vendre » stays, saying so, the farm still sells at the farm. Paid is never hidden: a paid Pro keeps delivery, Wave and Vitrine Plus (switching it is refused, a kind's switch leaves it), a spot paid for or running keeps « Mettre en avant » until it ends (feature_paid); Mara's gift is no payment. The shopper's refusals are plain French to anyone (vitrine_refuse, by triggers on orders, order_lines and wave_payments: place_order and the booking untouched); the owner's doors use feature_guard (a trigger on products for a new service, on orgs for the delivery numbers and the payout, set_storefront_style, the spots' functions). Not switched: « Photos des articles » — the vitrine's minimum and score, Le Chemin's photo step and its cauris, the photo slots bought with cauris, the cover and the logo all rest on them; hiding them cleanly would reshape all of that | built, 11 SQL tests (mutation-checked) + P1 before/after + 26 Flutter tests |
| Mara on a bad line (108, no migration), for every visitor of a shop's, a farm's or an association's vitrine and every business on the web: the deploy gives each file that changes between builds a folder named after its content (scripts/web-fingerprint.mjs: /app/<hash>/ main.dart.js and its parts, /ck/<hash>/ CanvasKit, /a/<hash>/ fonts, pictures, sounds), inlines Flutter's loader in index.html and writes the folders and the build in; the site Worker keeps those folders a year (immutable) and asks about the page, the workers and version.json every time, and answers « not found » for a gone build's folder instead of the page. web/mara_sw.js, registered once the app shows: the build's page and fixed-name files per build, every fingerprinted file cache-first and shared between builds — a second visit opens from the phone, offline too; a deploy is prepared beside the running build (only what changed: an app-only deploy fetches main.dart.js again, not the 1.5 MB engine) and taken at the next start, or on « Recharger », then the page reloads from the phone; the previous build's files are kept for a tab still on it; offline_sw.js is gone (« Télécharger pour hors ligne » asks mara_sw.js; push handlers in web/push_handlers.js, shared with push_sw.js). index.html: the seal drawn inline (SVG, 3 KB instead of 46 KB of base64), « Connexion lente — Mara arrive… », and when loading stops (a file that did not come, no network with nothing kept, 90 s of silence) « La connexion a coupé… » or « Pas de connexion… » with « Réessayer »; « Mise à jour de Mara… » while « Recharger » fetches the new build. Photos: the uploads Worker answers ?w=200|400|800 with a WebP made once by Cloudflare Images and kept under thumb/ (Postgres's yes for the photo itself first; the original when Images is absent or refuses — deploy-uploads.yml deploys without the binding if refused); the street's and the vitrine's tiles ask only near the screen and at their size (lazy_photo.dart) and decode at that size. Data: the street and the last 12 vitrines opened are kept on the device (street_cache.dart, the server's own rows): shown at once on the next visit while the fresh answer comes, and with no network « Pas de réseau — la vitrine de votre dernière visite »; a kept price is never charged (place_order decides). A vitrine's four questions are asked at once. The street's map is its own download. Mara's marks are lossless WebP (same pixels, under half the bytes). Measured on Chrome's 3G profile (562 ms, 1.44 Mbit/s), a vitrine of 12 photographed articles: first visit 8.8 MB → 3.3 MB, shop visible 25.4 s → 22.4 s, four photos 43 s → 23 s; second visit first frame 5.7 s → 1.8 s, shop visible 10.9 s → 3.2 s; offline nothing → the shop in 1.7 s. Android: nothing of this applies (the app is on the phone); a cold start with a live token no longer waits on the network: with the businesses on the device it settles on them at once (the code rules as always) and asks the server behind the screen — the second step first (asked, the page is kept and the code screen shown), then the list, the plan and the role; with none on the device the list is asked together with the other questions, not after them (one 12 s timeout at worst, not two); applies on the web too | built, Worker tests (uploads 7, site 6), script tests 4, Flutter tests (street cache 8, lazy photos 4), Chromium end-to-end (update path, offline, push) |
| Creating one's business, at once — no request to approve (111), for a shop, a farm and an association alike (a legacy church is created as an association): « Créer mon activité » asks one question a screen, a bar that fills, Retour and Suivant — the kind (three big tiles, under the welcome of Mara's creation page and only the kinds it offers), the name with its address marakaj.com/s/… written as it is typed and said free or taken at once (business_address_check, with a free one to take), what it does (a shop's line of trade: alimentation, téléphonie et électronique, vêtements et mode, beauté et cosmétique, restaurant et maquis, quincaillerie, autre; a farm's: volaille, élevage, maraîchage, céréales, mixte, autre; an association's kind of 102) and a sentence, the town (Burkina's largest in one tap) and the area, the phone (the proved WhatsApp number when there is one) and the currency of its country, then each of Mara's questions on a screen of its own, the summary and « Créer mon activité »; the answers wait on the device (per account) and the flow reopens where it was left. create_my_business() makes it on the server through create_org's own path (org_create_core: the business, its owner, its chart) and writes the town, area, phone and sentence where the business keeps them, so the first setup (091, 102) opens next — prefilled with them, so its vitrine step no longer clears the phone and address it does not retype — after the device code, asked once (108). Protection with no approval: one free business per person, a second only with Mara Pro (099's rule, on the server, two taps cannot make two); three creations a day at most per person (the journal counts them, a deleted business included); no address reserved for Mara — its names and help words (mara, marakaj, kaj, admin, support, aide…), payment and infrastructure names (wave, api, www, the Workers'), every first path of the app and the site (connexion, console, vitrines, s, o, livreur, mon-compte…), read without hyphens or trailing digits — refused at creation, said by the address check as it is typed, and refused when a business's admin renames its address (103's update_org rebuilt with that one check; Mara's own « Nouvelle entreprise » and fiche are not asked); Réglages › Création d'activité › « Numéro WhatsApp vérifié avant de créer une activité » (`create_phone_verified`, **off as installed**; on, no proved number, no business — the 109 verify screen asks it in the flow); a new vitrine reaches the street only with its minimum (092, unchanged). Entry points: the no-business screen (« Vous avez une activité ? »), the picker's « Nouvelle activité », Compte's « Créer une autre activité » (the Pro lock kept), the shopper's profile (`Routes.createBusiness` = /creer-mon-activite). The approval path is gone for people: no « Envoyer la demande »; the command center's « Demandes » is « Activités créées » (platform_created_businesses: what people created, with their answers and who; the requests of before still readable, approved or refused with the reason) and « Parcours de création » (107's editor renamed, its preview the flow itself); À faire counts « Nouvelles activités (7 j) » (new_7, its list behind it) and carries 113's `reports_open`; each creation is in the platform's journal. An older app's request (apply_for_org) is answered at once: written closed with « Mettez à jour Mara : vous créez maintenant votre activité vous-même » (the older app shows it under the request), the person rung with it, Mara not (030's ring now for a waiting request only), nothing waiting in À faire; the approval functions stay for a request from before, which a direct creation closes with the business it became; /demander-une-entreprise opens the creation. On a bad line the business just created is added to the session from what the creation knows when the list times out, and the answers stay on the device until the app has it. The platform's own « Nouvelle entreprise » stays. Fix on the way: create_org gave a farm the generic chart (no farm branch since 011) — a farm now gets the farm chart whoever makes it | built, 19 SQL tests (035's create_org put back and compared; 24 mutants all caught), 20 Flutter tests |
| Becoming a courier, approved by the platform (112), for anyone — a shopper, or the people of a shop, a farm or an association, since a courier is a person, not a business: « Devenir livreur » (/devenir-livreur) from the street's foot, the courier space's pitch and the shopper's profile opens a dossier, one question per screen with its progress bar, kept on the server step by step so it resumes on any phone — the town and its quartiers as chips; the days and hours; moto, vélo, voiture, tricycle or à pied (a motor vehicle's make, model, colour and plate); a selfie with the front camera (« le visage en entier, sans lunettes de soleil ni casquette »); the CNIB, passeport or carte consulaire front and back, and for a moto or a car the driving licence — optional unless Réglages › « Permis de conduire obligatoire » (courier_licence_required, off); the WhatsApp number, proved with 109's code (required once Réglages › « Numéro WhatsApp vérifié pour devenir livreur », courier_phone_verified, is on — off until 109's WhatsApp code is set up); the payout mobile-money number only while the platform takes mobile payment (076's wave_checkout), otherwise « Vos courses vous sont payées en espèces »; the driver charter, its accepted version kept; a summary, then « Envoyer ma demande ». The status page says « En cours d'examen » with the dossier's history, asks again on its own, and opens the courier space once approved. « Livreurs à valider » lists the dossiers (oldest waiting first; then « À corriger par le livreur »); a dossier's review page shows the selfie beside the ID, the vehicle, the quartiers and hours, the number and whether WhatsApp proved it, the charter and the history, and answers « Approuver », « Refuser » with a ready reason (photo floue, pièce illisible, visage différent, informations manquantes, autre — with a word) and the steps to redo, or « Demander une nouvelle photo » (selfie or ID): each journaled with its « Annuler » (never under a running course, never once the photos are gone) and rung to the applicant, whose refused step alone reopens, the rest kept. The courier row is « pending » while the platform examines it, so 105's count, platform_couriers() and an older app read it as before; register_courier and decide_courier are unchanged for that app. THE PHOTOS: under their own prefix courier/<user>/ in the bucket, written and read only by the uploads Worker's courier routes, each asking Postgres as the caller — a key only for a step the applicant may fill, a read only for a platform admin and a current photo (private, no-store), never for the applicant, another person, a business owner of any kind or the street; the org routes and thumbnails serve org/ only and refuse a key that spells its way out; documents can never name a courier key; the tables have row-level security and no policy. Deleted 30 days after a refusal (and at once once replaced, an upload never finished, a draft left 30 days, the account deleted): never served again from that moment, the bytes deleted the next time the platform opens its couriers or the applicant their dossier (no new scheduler). The privacy page says so | built, 27 SQL tests (6 mutations caught), 12 Worker tests, 14 Flutter tests |
| The shopper's page (113), « Mon profil » for an account that shops (the street's corner › Mon profil; a business's people keep their Compte and find « Mes achats » there — orders, favourite vitrines, addresses — the same for a shop, a farm and an association): the photo Google gave (else the initial), the name (« Mes informations »), the WhatsApp number with ✓ when proved — « Vérifier » (109's screen) only once the platform asks for a proved number, i.e. the WhatsApp code is set up — and the city; « Mes commandes » with « Recommander » on a finished order (« Réserver à nouveau » for a booking): my_order_basket says what of that order the vitrine still has, at most what is left (101) — half a kilo left is half a kilo —, nothing when it takes no orders (110), and the vitrine opens on its basket refilled (what was already in it stays), the lines gone said; « Mes réservations » (098's bookings alone); « Mes vitrines favorites »: ♥ on a vitrine's band and on each street card (signed in only — the stranger's street is as it was), one news switch per vitrine and one for all; the owner's new article or service on the vitrine, or a lower price, rings each follower ONCE per vitrine per day (the day's bell row said again « 4 nouveautés chez … : A, B, C… », written by a trigger on products in one statement for all the followers, left as it is after 20 novelties of a day — 2,000 followers × 30 articles in under 4 s —, no scheduler, never in the way of the owner's write), only what the street sees (open, at its minimum, 110's « À vendre » and « Services » switches), never the business's own people; the push opens the vitrine (workers/push); « Mes adresses de livraison »: Maison, Travail (once each) and others, ten in all, the words, a note for the courier and a pin (GPS, a Google Maps link, the small map to move it); the order sheet offers them as chips once « Livraison » is chosen, the first picked with its pin and price — place_order unchanged; « Paiement préféré »: cash, and Wave only while the platform's « Payer en ligne par Wave » (wave_checkout) is on — RULE M, not drawn otherwise, refused by the server, read back as cash once closed — the order sheet's first choice where the vitrine takes Wave; RULE M as decided (coordinator): the order sheet keeps following the vitrine's own Wave — 090's « Wave autorisé » ticked by the platform for that business plus 110's « Paiement en ligne » switch, which IS Mara allowing mobile payment for that vitrine — while the shopper profile's preference and the courier's payout number follow the platform switch wave_checkout; the preference only picks the sheet's first choice and never draws Wave where the vitrine does not take it; Notifications (the bell's list, now reachable by a shopper), Sons, Langue linked; « Devenir livreur » (112) / « Espace livreur », « Créer mon activité » (111), « Parrainer un ami » (shoppers have no code: marakaj.com on WhatsApp); Aide: « Écrire à Mara sur WhatsApp » once Réglages › « Numéro WhatsApp de l'aide Mara » (support_whatsapp, empty as installed, digits checked) is set — business Compte's « Contacter le support » uses it too, its old placeholder until then — and « Signaler un problème » (a topic, ten letters, five a day) → À faire « Signalements » (111's count), a sheet where Mara reads, reaches the person, closes with a word (journaled, « Annuler »), the person told in the bell; « Mes données »: « Télécharger mes données » (one JSON: profile, settings, addresses, favourites, orders with lines, reports) and « Supprimer mon compte » by typing SUPPRIMER, through the existing account Worker (POST /v1/me/delete: Postgres answers the caller's own id or why not — a business they belong to, a courier's file, an order open, a platform account, and anybody a « no action » key to profiles still names, e.g. a former employee's sales or articles, read from the catalogue; a GoTrue failure all the same is said « La suppression n'a pas pu se faire — écrivez à Mara. », 409); the cascades take the profile, follows, addresses, settings, reports and bell, while the person's orders stay with the shops — orders.customer_id now « on delete set null », a trigger writing « Client supprimé » and emptying the phone, address and pin, the order's lines, events, stock moves and sale (a handed-over order's books) kept; the privacy page says both. Tables shopper_settings, vitrine_follows, shopper_addresses, problem_reports: RLS on, no policy, every door the caller's own or the platform's | built, 12 SQL tests (16 mutations caught; 2,000 followers × 30 articles timed), 5 Worker tests + 1 push routing, 28 Flutter tests |
| The bell for everyone (115, batch 115 N), for a shop, a farm and an association (a legacy church as an association), the shopper and the courier: the bell on every home, on every tool page of a business (PageBell, at the top bar's end, the page's actions moved one place left), on the street and the vitrine for a signed-in shopper, the shopper's profile, the courier's space and the command center — each its own list (notifications.scope: shop/org, customer, courier, platform, plus the account's own « me » rows in each), a red bubble, « 9+ » past nine, live (Realtime under the table's RLS, the return to the app, a 60 s poll; one keeper for the app); a list marks read exactly the rows it showed (markAllRead removed: one business's list used to clear every list); notification_counts(). Push: « Activer » on every home of the three kinds, the shopper's profile, the courier's space, the command center; a device already allowed but missing from push_subscriptions is written back silently at sign-in and on return (the bug: the shop's home hid the offer once the browser said yes, so such browsers never rang); the subscription made on the active worker (mara_sw.js, push_sw.js only when none is active), the browser's question asked at the tap; Android FCM (firebase_messaging; POST_NOTIFICATIONS; push_subscriptions.platform + fcm_token, save_fcm_token, push_devices for the Worker; a tap opens the Worker's path); workers/push gains the FCM HTTP v1 sender (service account from the FCM_SERVICE_ACCOUNT secret, RS256 JWT on WebCrypto, never logged; dormant without it), customer pushes now open « Mes commandes » (they opened the shop's orders) and new_order the shop's Commandes (it opened the home). « M'envoyer une notification test » (Compte › Notifications, the shopper's profile, every list's settings) and « Tester la notification » (Réglages: devices + whether the webhook exists). Per-type switches (notification_prefs, my_notification_prefs, set_notification_pref; a BEFORE INSERT gate on notifications: off = no row, so no push; account and decision messages have no switch; the courier's 7-day nudge off by default). New bells: a refusal with its reason (refuse_order; orders.refusal_reason; decide_order keeps its two arguments), the phone verified, the courier's dossier received, a delivery near them (the shop's own couriers at once, the city's after the shop's minutes — pg_cron deliveries-waiting), a shop adding them, the cash confirmed, the 7-day nudge (pg_cron courier-idle). Not done: a booking reminder the day before (a booking's date is free text). Mara's message « Responsables » (default, as before) or « Toute l'équipe » (platform_message_send; send_platform_message unchanged for its callers; params per 099). The bar's numbers (home_counts): orders and bookings to answer, articles at zero or under their level (shop, farm), invoices past due, credits past their due date (117), invitations unclaimed, a farm's supplies low and batches with nothing written today; on Plus the sum of its lines; an association's bookings (no place on its bar) and Membres (no due notion) not drawn | built, 11 SQL tests, 12 Worker tests, 13 Flutter tests |
| The farm's six, one entry at a time (115, W4; migration 119): « Réception », « Consommation » and « Perte », « Mortalité » (and a batch's weighing, vaccination, birds sold, a herd's birth or treatment), « Ajouter des animaux », « Ajouter une culture », « Récolte » are full-screen step flows on 115's StepFlow (one question a screen, summary, « C'est fait », answers kept on the device) and replace the farm's sheets (farm_sheets.dart and the new-flock/herd/crop and quantity sheets, gone). Offline exactly as before: a delivery, a feeding, a loss and a flock's event are written on the phone and drained by the outbox to receive_stock / move_stock / record_flock_event; opening a batch, a herd or a planting, a herd's event and a harvest need the network, as before, and say so on the summary. New on the way: a priced delivery is filed under the farm chart's right account (Aliment, Vétérinaire, Semences, Engrais et traitements, Fournitures ferme — 009 filed every one as Aliment), the supplier in its note; a feeding names the batch or group it went to (in the movement's note — move_stock keeps no batch); a consumption or loss offers only what was received (nothing received: « Enregistrer une réception »), stopped on the phone past what is left (101); animals: species tiles (poultry is a flock, any other animal a herd), the name, how many, since when (today, a day, or their age — the day counted back so the batch's age reads right), what they cost (an expense « Achat d'animaux » through the outbox), the new batch cached at once for « Mortalité » offline; a crop: the crop, the plot (found or created from its name), its area (written on the plot), the sowing day, the unit, the harvest expected; a harvest: the planting, how much, the quality, where it goes — « Gardée pour vendre » or « Vendue tout de suite » counts it onto the farm's « À vendre » article of that crop's name in the same transaction (119: record_harvest(…, p_to_stock); none yet, one is made at price 0 and off the vitrine; one put away comes back; an article sold by another unit is asked in its unit, the server refusing kilos added to trays; a service of that name refused; never a purchase, never income), then the farm's « Vente » for one sold now; « Pour la maison » moves nothing, as every harvest before; with 119 not yet live the harvest is counted the 019 way and the screen says the shelf did not move. A farm only; a shop and an association are not touched | built, 10 SQL tests, 26 Flutter tests (16 new + 101's feed stop on the flow) |
| One entry at a time for the money (115, W2; migration 117), for a shop, a farm and an association alike, on 115's shared step flow (one question a screen, « Suivant », the summary, « Enregistrer », « C'est fait », answers kept on the phone): « Facture » — for whom (the names already billed offered), how to reach them (optional), the business's articles and services picked one at a time or a line typed, how many at what price, when due (à réception, 7/15/30/60 jours, a date), an internal note, the preview, « Créer la facture » (create_invoice, one client_uuid per invoice so a retry cannot raise it twice; online as before, the number is the server's), then « Voir et partager la facture »; the correction (040) is the same flow opened filled and saved through revise_invoice — the old form and its two routes are gone. « Carnet de crédit » — « Nouveau crédit »: who, their WhatsApp number (optional), a sum or articles (a shop and a farm; an association lends sums), the sum and what for (record_credit_sale, online as before) or the « Vente » flow opened on Crédit with the customer filled in (record_sale, offline through the outbox as any sale), when they will pay (optional), « Envoyer un rappel sur WhatsApp »; « Remboursement »: who → how much → Enregistrer. 117: debts.due_on (none for every debt of before, never overdue), set_debt_due (by the debt, or by the credit sale's client_uuid — queued behind a sale still on the phone; a sale the server refused dates nothing), repay_customer (spread over the customer's debts oldest first through 024's record_debt_payment, one transaction, once per client_uuid, never past what is owed), debt_dates (the carnet's « À payer le » / « En retard depuis le » in red, and the reminder's date); 104's customer_debts and debts_of_customer untouched. « Recette » (an association and a legacy church): Cotisation, Don, Vente or Autre, who (the members list, or a name typed), the amount, how — the church words are no longer offered to any association, a legacy church included (no « dîmes », « offrandes », « collectes spéciales » chips, no « Offrande du dimanche » / « collecte du dimanche » hints, the Église kind's line reworded); the accounts already in the books keep their names. « Dépense » for all three: the business's own expense headings as big tiles (« Autre » names a new one), the amount, how, a word, the receipt's photo (taken, from the phone, or « Choisir dans Photos », 114) — record_entry through the outbox, offline, as the association's sheet did; a shop and a farm, which had no way to record an expense, find it in Plus › Dépense. The old recording sheet, the free-details editor, the credit-sale sheet and the per-debt repayment dialog are gone | built, 6 SQL tests (19 mutants, 16 caught, 3 equivalent), 19 Flutter tests (7 new, 12 rewritten) |
| Three entries one step at a time (batch 115, W3; 118), for a shop, a farm and an association (a legacy church as an association) — on the shared step flow (W1): « Production » (shop and farm; an association has no production tool): what you made → what you used (the articles marked « Utilisé en production », recently used first, « Voir tous mes articles » for the rest; with none marked: « Ajoutez d'abord vos ingrédients comme articles et cochez "Utilisé en production" » and a button opening the article flow with that box ticked, back to the same step with the list read again) → how much of each (the stock shown, more than the stock said) → how many made (the cost of one shown) → the price (optional, said when under the cost) → the summary with the total cost and the cost of one → record_production (026) as before, the price set after as before; « Refaire » prefills a past run; the old sheet and its picker are gone. « Commandes » (a shop's and a farm's orders, an association's bookings): each card's one button opens the order where it stands — see it, accept, or refuse with a reason (three taps or its own words; 115's refuse_order keeps it and tells the customer, decide_order without it before 115) → prepare (tick each article, « 2 sur 2 prêts »; a booking skips it) → « Prête » (the customer told by the server, builder N) → handed over / delivered / « Je la livre moi-même » / the service done → « Avez-vous reçu l'argent ? » (set_order_paid) — each stage through the functions the buttons called; the order books its own sale on completion (101), nothing rings the till; « Annuler la commande » inside. « Équipe » › « Ajouter une personne »: the name (and function), the WhatsApp number (the country's length checked), the responsibility with one line each — only those below the caller's (103's ladder, held by invite_employee), what they will see (admin: everything and the settings; observer: everything, nothing recorded; the others the owner's dial for their tier, Caché/Voir/Modifier per tool) and « Tout le détail » / « Seulement les totaux », the salary (optional, per month/week/day) → « Créer l'invitation » → the code, the QR and « Envoyer sur WhatsApp » (straight to their number, else the share sheet); the invitation sheet is gone. 118: pending_invitations.salary / salary_period (null for every invitation before: P1), set_invitation_salary(invitation, amount, period) — an unclaimed invitation of a business the caller administers, the owner (or the platform) for any, another admin only for a responsibility below their own, never an owner's; 0 clears — and a trigger on the claim (by code or the sign-in sweep) writing the person's payroll row as set_member_salary does (their row, an unlinked one of the same name, else a new permanent one; an hourly row left alone), never in the way of the claim. The app keeps working before 118 (the invitation is made, the salary said to be noted in Équipe later) | built, 6 SQL tests, 10 Flutter tests |
| Batch 120 (no migration — 120 stays free): Android push that registers, asked at every opening, each kind's word at the end of the setup, the command center's keyboard. Why no phone ever registered: release android-243 (the APK installed) was built before the GOOGLE_SERVICES_JSON secret existed — its « Install Firebase's config » step was skipped and the APK has no google_app_id, so Firebase.initializeApp failed and the app offered nothing; run 244 (manual, with the secret) built the right APK but a manual run never published. Build App now publishes a manual run on main too; the README says to install an APK built after the secret (and that the secret is the raw file, not base64). « Diagnostic de cet appareil » under Réglages › « Tester la notification » and Compte › Notifications: platform, Firebase started (and why not), the device's permission (MainActivity's `bf.kaj.app/notify` channel: granted / still askable / blocked, which Firebase cannot tell apart), the token or the browser's subscription and its service worker, saved on the server; « Réessayer l'enregistrement ». « Activer les notifications ? » for every signed-in person (shopper, courier, member of a shop, a farm or an association, the platform) at a cold start, a sign-in and a return after an hour, while this device is not in their book and could be: « Activer » asks the device from the tap (a browser's gesture), « Plus tard » asks at the next opening; blocked, it explains and offers « Ouvrir les réglages » (the app's notification settings; a browser: the padlock). Never twice in one opening, never over the code, the second step, a first setup or the creation of a business. The end of the setup says « Votre boutique / ferme / association est prête » and « Ouvrir ma boutique / ma ferme / mon association » (a farm was told « Ouvrir ma boutique »); a farm's settings, its league line, the street's corner button, « Mettre en avant » and a farm's or an association's vitrine (the order sheet, the search) no longer call it a boutique. The command center went white when the keyboard rose: the shell handed its page the MediaQuery from above its own Scaffold, keyboard included, so the page's Scaffold took the keyboard off twice (a body of nothing); read from inside now — every section, the fiche's tabs, Types d'activité, Parcours de création, Réglages; the fiche's vitrine editor had the same fault | built, 19 Flutter tests |
| Mara Pro by card, charged in dollars (121), for a shop, a farm and an association alike (Mara Pro is one price for the three kinds): Mara's Stripe account is in the US, so every price the app shows stays in FCFA as before and Stripe Checkout charges USD. A new platform setting `stripe_xof_per_usd` (seeded 600) — Réglages › Mara Pro « Taux pour la carte : FCFA pour 1 $ », a whole number above zero (121's platform_set_setting refuses 0, the dialog says it first), journaled with « Annuler ». The conversion is the server's: stripe_usd_cents() = ceil(price × 100 / rate), rounded up to the cent and computed in numeric (a price already in USD is charged as it is; another currency, no readable rate, under Stripe's 50 cents or above its 99 999 999 — a rate of 1 on a 30 000 000 F year — no card, said in French, plan_terms never fails); stripe_begin() answers the cents and 'usd' (the Worker sends them as they are, never converts) and the FCFA price, which the line's name says (« Mara Pro · Mensuel · 15 000 FCFA · <business> »); plan_terms() says the same cents (stripe_usd_month / stripe_usd_year), and the card button shows « ≈ $25.00 par mois, payé en dollars » under its FCFA price. stripe_settle untouched (it reads no amount); no subscription was live when this shipped. Order: apply 121 live, then deploy the pay Worker (an older Worker against 121 already charges the right dollars; a newer one against a database before 121 charges as it is told), then the app | built, 7 SQL tests (test_batch121) + test_stripe_pro's amounts, 20 Worker tests, 6 Flutter tests |
| Couriers within a radius (122, batch 122 S1), for a shop, a farm and an association alike (a delivery is an order of any kind with a vitrine): « Delivery guys receive requests around 10 km. » A new platform setting `courier_radius_km` (seeded 10) — Réglages › Livraison « Distance où les livreurs reçoivent une livraison (km, 1 à 100) », a whole number from 1 to 100 (122's platform_set_setting refuses the rest, the dialog says it first), journaled. couriers gains last_lat / last_lng / last_seen_at: the courier's last known position, kept by delivery_board when the phone gives one (nothing stored a position before; a courier reads only their own row); « fresh » is seen within 24 h — an older one is ignored — and every board read forgets the positions older than 30 days (the privacy texts say so). courier_reach(courier, shop, lat, lng) is the one rule: 'near' / 'far' when a fresh position and the shop's pin both measure (the radius), else 'city' (115's rule, both declared cities the same), else 'unknown' (a declared city or quartier has no coordinates anywhere, so there is no zone centre to measure from). The bell — tell_couriers (115's, redefined) — rings for the street's 'near' and 'city' only; the shop's own couriers always, the cap 50, deliveries_waiting unchanged. The board — delivery_board (073's, redefined, no longer « stable » since it keeps the position) — is wider: every street delivery as before except the known 'far' (live, both approved couriers have neither city nor position, and a board by the bell's rule would be empty for them); the own first, then near (nearest), city, unknown; to_shop_km from the fresh position is the tag (« à X km », or nothing). The app asks for the current position when the board opens (Android and web, with one line saying why: « Pour voir les livraisons à moins de N km »), falls back quietly, and an empty board says « Activez la position pour voir les livraisons proches » when it has neither a position nor a city. take_delivery unchanged; 061's older available_deliveries (the app's fallback before 073) is left as it was. Order: apply 122 live, then merge (the app's Réglages rows are only shown when the server has the keys) | built, 8 SQL tests (test_batch122) + test_batch105's key list, Flutter tests |
| « Download the app » on a phone's browser (122, batch 122 S2), for the shopper of a shop's, a farm's or an association's vitrine alike: on the street and on a vitrine, in a phone's browser only (never a computer, never the installed web app, never the Android app), a small card at the top once every seven days (« Plus tard »): Android — Google Play once Réglages › Applications mobiles « Mara est publiée sur Google Play » (play_store_live, seeded off) is on, the GitHub APK until then; iPhone — the App Store once « Adresse de Mara sur l'App Store » (app_store_url, an https address or nothing) is set, else how to add Mara to the home screen (Safari › Partager › « Sur l'écran d'accueil »). The links come from app_store_links(), granted to anon (063's rule; in test_least_privilege's street list). It belongs to the page, so an order sheet or the sign-in sheet covers it | built, SQL in test_batch122 TEST 6–7, 9 Flutter tests |
| Mara for iPhone, prepared for Codemagic (batch 122 S3): CLAUDE.md now ships web, Android and iOS (never macos/windows/linux). app/ios from `flutter create --platforms=ios`, tracked: bundle id bf.kaj.app, name « Mara », iOS 15.5 (google_mlkit's podspecs; Firebase asks 15.0), the icons from the brand kit's app-icon-1024, the Android launch seal on its ground, French and English usage strings (camera, photos, location in use, Face ID; Info.plist + fr/en InfoPlist.strings), URL scheme bf.kaj.app for the Google sign-in's return, export compliance answered, Podfile platform 15.5. Firebase's GoogleService-Info.plist is written at build time from GOOGLE_SERVICE_INFO_PLIST and copied by a build phase when there (never committed). codemagic.yaml: workflow ios-release, Flutter stable, `flutter build ipa` with build.yml's --dart-define list + STORE=appstore (update_check: an App Store build never shows the APK banner), automatic signing from the App Store Connect API key integration, TestFlight. README « Building for iPhone with Codemagic ». No iOS build can run in this container; closed-app push on iPhone is not switched on (Android-only push code, APNs to set up) | prepared — first Codemagic build to run |
| Migration numbers 114, 116 and 120: unused — 114 and 116 retired during batch 115, 120 during batch 120/121 (batch 120 needed no migration; Stripe in dollars took 121), no file carries them (the bundle `database/apply_006_to_122.sql` goes 113 → 115 → 117 → 118 → 119 → 121 → 122); the next migration is 123 | retired, never to be reused |
| Cauris, spending (085): a Pro tool opens for 30 days for its price in cauris (the console's list: Analyses 400, Livraison 600, Paiement en ligne 500, Vitrine personnalisée 300, Comptabilité 500 after 60 days on Mara, Équipe 400, Paie 400, Devises 300, Tontines 500 after 90 days; Mara Pro complet 1 500), in one ledger line, 30 more days when bought again; Mara Pro complet makes the business Pro (org_plan) for its 30 days, so every Pro rule follows. One question for every guard — org_has(business, tool): pro_locked, feature_access, delivery, online payment and the dressed vitrine ask it. The app draws each Pro tool grey with « PRO · 400 » and a cauri; its door says what it costs, what the wallet holds and how many are missing, opens it in one tap, or leads to how to earn and to Mara Pro; the comparison page prices each tool in cauris in the Free column and offers « Ou gagnez Mara Pro ». Basic, step by step, for businesses that start from now on (the ones already here keep everything): the street at 60 % (the directory's own rule), invoices and receipts, production and the credit book at 90 %, a second business after 10 orders, with 7 days of trial; a ring on the home fills with the vitrine and says what each step opens | built, 7 SQL tests + 7 Flutter tests |
| Cauris, earning (084): Mara's points, earned by doing well and nothing else. An append-only ledger, unique per (business, reason, ref) so nothing earns twice; rules and daily caps the platform edits in Console › Mara Pro › Cauris (order finished +10, customer back +15, accepted within 15 min +3, a distinct visitor +1 up to 30 a day, the till 7 days running +20, the farm's log +5 a day, vitrine complete +50, a business brought in that took off +200, an accepted order dropped −10). Earned from the events themselves — never from the business's own people, never under 500 F, at most 2 a customer a day; the device's own random id counts visitors, not reloads. An idle wallet expires after 180 days. « Mes cauris » (Compte, the shop's and the farm's menus): the balance counting up, this week's score, how to earn, the referral code to send on WhatsApp, the history line by line. The console lists the week's top earners and flags the ones whose orders come mostly from one customer. Associations earn none | built, 8 SQL tests + 3 Flutter tests |
| A farm has a vitrine (083): « À vendre » on the farm's menu, with « Commandes » beside it — what it sells (eggs, poultry, harvest) as articles, so the street's order, basket, delivery and payment are the shop's own; each with its photo, price and unit (« 2 500 F / plateau », products.unit), how many there are (counted by hand: grown, not bought, so no purchase is booked), and, for a batch or a harvest still to come, the day it will be ready (products.available_from) — a pre-order, orderable before there is stock; the vitrine reads « Retrait à la ferme », its strip speaks of the farm, the settings explain the farm's vitrine | built, 4 SQL tests + 2 Flutter tests |
| Mara's slogan, « Au Service du Peuple »: the street's headline (« Les boutiques près de vous » moves into the line under it), the footer under « mara », the tab and the install name, the share card's line, the README and the store texts | built, 1 Flutter test + 2 updated |
| The vitrine's foot, the owner's way: « Toutes les vitrines » on the page, then the footer proper — one centred cream band with « mara » and its line, « POWERED BY » over Kaj Consulting's logo, © the year — on every street page; the basket a card floating over the page (never glued to the footer) naming each article picked, with a small square of its photo (its initial when it has none) and « ×2 » when there are two, above the count, the total and « Commander »; the street's ink, cream and lines in Mara's tones | built, 2 Flutter tests |
| The app is Mara, powered by Kaj: the seal as every icon (web, favicon, PWA, Android with its adaptive icon), Mara's seal on indigo before the app (Android's launch screen, the web page, the Flutter splash — one picture), the seal and « mara » on the sign-in, the seal on the code screen and the lost page, « mara » in the street's header and footer above « POWERED BY » and Kaj Consulting's logo, the street's strip in Mara's indigo; the app's own palette Mara indigo with the seal's terracotta, gold and green as tints (a business that chose « Lagune » keeps it); every « Kaj » the person reads is « Mara », « Kaj Pro » is « Mara Pro » — the database's sentences read through `brandText`, the push Worker's likewise; the tab, the install, the launcher and the share card (the brand's feature graphic) say Mara. Internal names unchanged | built, 3 Flutter tests + 1 Worker test |
| Kaj Pro by card, as a Stripe subscription (082): « S'abonner par carte · <price> » on the comparison page, for an admin, once the platform switches it on (Console › Kaj Pro, `stripe_on`), monthly or yearly at the console's own Pro prices (one price wherever it is paid). The kaj-pay Worker opens Stripe Checkout (`stripe_begin`, under the owner's identity, amount from the database), takes Stripe's signed webhook, re-reads the subscription and calls `stripe_settle` (service role only): Pro to the paid end plus a day, renewals move it on, a cancellation keeps what was paid, a longer Wave date or an endless gift is never shortened. Back from Stripe the page thanks the owner and reads the business again until Pro shows; a business paying by card sees its renewal date and Stripe's page to change the card or cancel. Dormant until STRIPE_SECRET_KEY / STRIPE_WEBHOOK_SECRET are set | built, 7 SQL tests + 11 Worker tests + 8 Flutter tests |
| A shop's own logo (080), for every plan: Paramètres › Identité › Logo — take or choose a picture, saved at once as one of the shop's photos (`set_org_logo`, administrators, its own non-PDF photos only), « Changer », « Retirer »; the vitrine shows it whole in a white square beside the name; `storefront()` carries it in `style` for Free and Pro alike (no Pro dressing gained); `storefront_photo_allowed()` serves it to the street while the vitrine is open. Not yet on the directory's shop cards | built, 3 SQL tests + 3 Flutter tests |

**Not built**

Custom domains. Reading an invitation QR with the camera — today the invitee
types the code, though the scanner built for barcodes is now most of what
that needs. Attributing a contribution
to a named church member from the recording sheet (the SQL and the giving
statement both support it; the sheet has no member picker yet). An invoice
leaves as a rendered image, which is what WhatsApp actually wants — a true PDF
export is still not built.

**Not yet verified**

None of the network paths has been exercised against a real Supabase project:
no credentials. Specifically unproven end to end —

- The SMS round trip. Phone sign-in needs an SMS provider enabled under
  Authentication → Providers → Phone.
- Email sign-up, which behaves differently depending on whether "Confirm email"
  is on. The app handles both (`response.session == null` means the account
  exists and nobody is signed in yet), but only one of the two has ever run.
- `SyncService` posting `record_entry`, `record_transfer`, `receive_stock`,
  `move_stock`, `record_flock_event` and `record_eggs`. The payload keys are
  asserted against the SQL signatures in `app/test/record_entry_test.dart` and
  `app/test/farm_offline_test.dart`, which is the failure this would otherwise
  produce on somebody's phone days later, but no request has actually been
  made.

Also unproven: the upload Worker. `workers/uploads/` has never had a real
photograph put through it, because it needs a deployed Worker with an R2
binding and a live Supabase token. Its authorisation is delegated entirely to
RLS, which *is* tested — `database/tests/test_capture.sql` is one shop
reaching for another's pictures — but the HTTP path itself has not run.

Everything below the network — routing, org resolution, the offline path, the
ledger, the policies, the reports, the log, the farm's two ledgers, the shop's
counter, the payroll and the capture queue — is covered by 147 Flutter tests
and fifteen SQL suites (178 assertions).

**Numéros vérifiés par WhatsApp (109) — the owner's setup**

Nothing of this is needed for 109 to go live: the switch is off, and ordering
is as before. It is needed before the switch is turned on — until then a code
could not reach anybody, and nobody could order. No key, token or secret is
ever written in the repository or in a chat: each goes straight into the
place named below.

1. **Meta Business.** In business.facebook.com, the business that is Mara (Kaj
   Consulting); verify the business when Meta asks (it lifts the low daily
   message limits).
2. **A WhatsApp number.** developers.facebook.com › My apps › create an app of
   type *Business* › add *WhatsApp*. Add Mara's sender number (a number not
   already used in the WhatsApp app on a phone) and verify it. Note its
   **Phone number ID** (WhatsApp › API Setup).
3. **The template.** WhatsApp Manager › Message templates › Create: category
   **Authentication**, language **French (fr)**, « Copy code » button, the
   security disclaimer on, an expiry of 10 minutes. Note its **name** (for
   example `mara_code`) and wait until it is *Active*. (Another language: set
   `WHATSAPP_LANGUAGE` in workers/whatsapp-otp/wrangler.toml.)
4. **The token.** Business settings › Users › System users › add one (Admin),
   *Add assets* › the app and the WhatsApp account, *Generate token* with
   `whatsapp_business_messaging` (and `whatsapp_business_management`), never
   expiring. It is shown once.
5. **The hook's secret.** Supabase › Authentication › Auth Hooks › *Send SMS
   hook* › HTTPS › *Generate secret*: it reads `v1,whsec_…`. Leave the hook off
   for now (the URL is not there yet).
6. **GitHub secrets** (repository › Settings › Secrets and variables ›
   Actions): `WHATSAPP_TOKEN` (4), `WHATSAPP_PHONE_ID` (2),
   `WHATSAPP_TEMPLATE` (3), `SEND_SMS_HOOK_SECRET` (5). `CLOUDFLARE_API_TOKEN`
   and `CLOUDFLARE_ACCOUNT_ID` are the ones the other Workers already use.
7. **Deploy.** Actions › *Deploy the WhatsApp code Worker* › Run workflow. It
   runs the Worker's tests, deploys `kaj-whatsapp-otp` and hands the four
   secrets to Cloudflare's secret store. Open
   `https://kaj-whatsapp-otp.<subdomain>.workers.dev/v1/health`: it must say
   `{"ready":true}`.
8. **Turn the Phone provider on, then plug the hook.** Supabase ›
   Authentication › Sign In / Providers › **Phone** › *Enable* — it MUST be
   on: while it is off Supabase sends no phone code at all, a phone *change*
   included, and never calls the Send SMS hook (Supabase's documentation of
   the hook). Leave its SMS provider unset: **no SMS provider (Twilio,
   MessageBird, Vonage…) is needed** — the hook replaces it. Then Auth Hooks ›
   Send SMS hook: URL
   `https://kaj-whatsapp-otp.<subdomain>.workers.dev/v1/send-sms`, the secret
   of step 5, *Enable*. What turning Phone on opens, and what it does not:
   * a person whose number is already proved can also sign in with that
     number and a code (Supabase's phone sign-in — the app shows no such
     button, but the API allows it); the code comes on WhatsApp like the
     others, so whoever reads that WhatsApp can open the account — the same
     trust the order already puts in the number;
   * a sign-up with a phone alone is refused: the Worker sends no code to an
     account with no e-mail (« Un numéro se vérifie depuis un compte Mara
     existant. », 403 — workers/whatsapp-otp/src/index.js, tested by « a
     phone-only sign-up (no e-mail) is refused and nothing is sent »), so a
     number alone never receives a code and never becomes a way into Mara.
   Supabase's SMS OTP settings apply to these codes: keep the length at
   **6** (the app asks six digits), the expiry at a few minutes; its rate
   limits too (Authentication › Rate limits) — the app waits 60 seconds
   before « Renvoyer ».
9. **Try it, then switch.** Command center › Réglages › Commandes de la rue ›
   « Numéro WhatsApp vérifié avant de commander » › Oui. Order from a vitrine
   with an account that has no proved number: the code must arrive on
   WhatsApp, and the order goes out with that number. If it does not arrive,
   « Annuler » in the Journal puts the switch back — ordering is then as
   before.

---

## M1 — Login and org resolution

The single highest-value change: it turns a one-church demo into a
multi-tenant product.

> Build authentication and org resolution.
>
> 1. Add a login screen: phone number + OTP as the primary method (most users
>    have no email), with email/password as a secondary option. Use Supabase
>    auth.
> 2. After sign-in, query the user's memberships. If they belong to exactly
>    one org, go straight to its home screen. If several, show a picker.
>    If none, show a "waiting for invitation" screen.
> 3. Delete the hardcoded orgId and orgName from main.dart. Everything must
>    come from the signed-in user's memberships.
> 4. Store the session so it survives weeks offline — Ignace has no signal.
>    Add a device PIN for re-entry when the token cannot be refreshed.
> 5. Route to the right home screen based on the org's `profile` column
>    ('church' | 'farm' | 'retail').
>
> Test on web with a real Supabase user before saying it works.

**Demo after M1:** two different people log in and see different businesses.

---

## M2 — Admin screens

> Build the admin section, visible only to owner/super_admin/admin roles.
>
> - Org settings: name, currency, profile.
> - Entities: create/edit/list (farm sites, church campuses, store branches).
> - Departments within entities.
> - People: list members, invite by phone or email, assign a role at a chosen
>   scope (org / entity / department), set observer visibility to full or
>   summary, revoke access.
> - Invitations via a short code or QR so a temp employee can join by scanning
>   Esperance's phone. No email required.
>
> Enforce with the existing RLS — an admin of one org must not touch another.

**Demo after M2:** you create a business, add staff, and hand out access without
touching SQL.

---

## M3 — Reports and the accountability loop

Israel's pastor and Ignace's investors are the reason the data gets entered
carefully. Make them visible.

> Build report screens over the existing SQL functions.
>
> - Weekly summary (church_weekly_summary) with a share-as-image/PDF button
>   for WhatsApp — likely the most-used feature in the app.
> - Cash balances (church_balances).
> - Member giving statements (member_giving_statement) for year-end.
> - Observer view: honour `visibility` — 'summary' sees totals only, 'full'
>   sees line items.
> - A "Close the day" button on the home screen: shows money in, money out,
>   what is pending, and a streak counter.

**Demo after M3:** the pastor gets a Sunday summary on WhatsApp automatically.

---

## M3.5 — Accounts, names, books and a console

Three gaps that only became visible once M1–M3 were on screen together.

**1. There was no way to get an account.** The only route in was an invitation
from somebody who already had the app, and the only way to be first was for
Kaj-consulting to run an INSERT. Sign-up now sits beside sign-in on the login
screen, and signing in with an unknown number is refused rather than silently
creating a second account for a mistyped digit. The order this teaches is
deliberate: make the account, then join the business with a code. An account on
its own grants nothing.

**2. Entries could not be named.** Four kinds of contribution and seven expense
categories, all compiled into the app and into 002. Anything real that was not
on that list got filed under whichever category was least wrong. That was
defended as protecting the books from seven spellings of "Loyer", but a
category list nobody can add to does not produce clean books — it produces
books where "Fournitures" means eleven things and no report can separate them.

> `record_entry()` takes the words the person typed. `ensure_account()` turns a
> name into an account the first time and finds the same one every time after,
> matching case-insensitively and on trimmed text, because that is how a name
> arrives from a phone keyboard. The chips are now the accounts the books
> already hold — so choosing one posts the exact stored name and cannot open a
> duplicate — and "Autre…" is a text field. Each entry also carries a note and
> any number of typed characteristics as jsonb.

**3. The ledger had been double-entry the whole time and nothing could show it
as one.** Journal, income statement, balance sheet, general ledger with a
running balance, trial balance, an editable chart of accounts, and transfers
between cash accounts — without which banking the Sunday offering is recorded
as earning it twice.

**4. Nothing recorded who changed what.** The ledger was always its own audit
trail, which covers money; every decision about *who may touch* the money was
silently mutable. An admin could grant themselves ownership, act, and revoke it
with no trace anywhere. `008_audit_log.sql` adds one append-only table, one
generic trigger, and RLS with a select policy and no insert, update or delete
policy at all — the only writer is the trigger, which runs outside policy, so
the owner of a business cannot erase their own history. Most of
`test_audit.sql` is them trying.

The console that reads it has three tabs because three different questions get
asked in the same five minutes: what happened (the log), what is actually
stored (every table, its purpose, this org's row count, its columns and
foreign keys), and what this phone is still holding — which finally reads
`outbox.last_error` and tells "waiting for signal" apart from "the server
refused this".

**Demo after M3.5:** somebody signs themselves up, joins with a code, records
"Réparation du toit" with the mason's name attached, and the owner opens the
income statement and sees it — then opens the log and sees who recorded it.

---

## M4 — Ignace's farm

> Add the farm profile module, following the patterns in
> 002_church_profile.sql.
>
> Schema (005_farm_profile.sql):
> - items (feed, medicine, supplies) with units and reorder thresholds
> - stock_movements (received, consumed, wasted) — append-only, like the ledger
> - flocks: batch id, bird count, arrival date, breed
> - flock_events: mortality, weight samples, vaccination
> - egg_production: date, flock, count, grade
> - customers and invoices with payment tracking
>
> Every write goes through a function that also writes the matching ledger
> entry — feed purchased is both a stock movement and an expense. Follow the
> record_contribution pattern exactly: plain-language inputs, accounting hidden,
> client_uuid for idempotency.
>
> Screens: home with today's feed/eggs/mortality, stock in/out, flock detail,
> egg sales, invoice creation and sharing.
>
> Add tests to database/tests/ proving the ledger stays balanced.

**Demo after M4:** Ignace records a feed delivery with no signal; his investor
sees the summary the next time either device syncs.

**Built.** `009_farm_profile.sql` (the plan numbered it 005; that slot went to
invitations while the farm waited). Two departures from the text above, both
deliberate:

- **Feed is expensed when bought, not when eaten.** The plan says "feed
  purchased is both a stock movement and an expense" and that is what was
  built. The strictly correct treatment capitalises it as inventory and
  expenses it on consumption, which would smooth the income statement and give
  the stock account a value. It is not done, because it matches how the money
  actually feels to the person paying for it — the day twenty sacks arrive is
  the day the money is gone — and because a real inventory valuation is a
  conversation with an accountant rather than something to guess at. Noted at
  the top of the migration.
- **Two writes need the server.** Opening a flock and raising an invoice are
  not offline-first, unlike the four things Ignace does every day. A batch code
  and an invoice number both have to be unique across the business, and two
  disconnected phones inventing the same one would split a cycle's figures in
  half with nothing to say so. Everything he does standing in a poultry house
  works with no signal; the two things he does sitting down do not.

The suite tests the four specific ways this module inflates profit: feed
expensed twice, eggs booked as income before anyone pays, an invoice earned
once when raised and again when settled, and a dead bird expensed on top of
the feed it already ate.

---

## M5 — Esperance's store

The hardest and highest-value module. Her losses come from data never captured.

> Add the retail profile module.
>
> Capture-first design: the home screen's primary action is a large camera
> button that creates a record with ZERO required fields. Photo now, details
> later or never. Every required field at capture time loses a user.
>
> - Photo upload to Cloudflare R2 (bucket `kaj-app-uploads` already exists),
>   path recorded in the existing `documents` table.
> - On-device OCR with Google ML Kit (free, works offline) to read product
>   name, serial number, expiry date, price from the photo. User confirms
>   with one tap rather than typing.
> - Barcode scanning for known products.
> - products: name, serial, barcode, expiry, cost, price, quantity, photos
> - sales and returns, tied to the ledger
> - employees: permanent and temporary, shifts, salary/wage, payments
> - Expiry alerts: "3 items expiring in 14 days — 82 000 at risk"
> - A running "losses avoided" total. This is the number that renews her
>   subscription.

**Demo after M5:** she photographs a delivery invoice and the products are in
the system without typing.

**Partly built.** `011_retail_profile.sql` and the store screens: products
with prices, counts and expiry dates, sales and returns posting through the
same `record_entry()` every other module uses, expiry alerts valued in money,
and a losses-avoided total. Selling is idempotent by `client_uuid`, so the
phone can retry.

Employees, shifts and payroll are built — `012_employees.sql`, and the
Personnel screen behind the store's home screen.

The capture half is built too — `013_capture.sql`, `workers/uploads/`, and the
camera button that is now the store's primary action. It takes a photograph
with zero required fields, keeps the bytes on the device until there is
signal, and files them in R2 under `org/<org_id>/…` through a Worker that
authorises by forwarding the caller's own token to PostgREST. Naming a picture
or attaching it to a product is a separate act, done later or never.

Two departures from the text above, both deliberate:

- **The upload is a Worker, not a pre-signed URL.** Pre-signing still needs a
  server to decide who may have a URL, and once that server exists the signing
  buys nothing but a second moving part that holds a key.
- **The photograph is recorded after the bytes land, never before.** A row
  pointing at an object that does not exist puts a broken thumbnail in a
  gallery with nothing the person holding the phone can do about it. The cost
  is orphaned objects when the app dies in between, which is a bucket
  lifecycle rule's problem rather than a schema's.

**Complete**, including the demo — *she photographs a delivery invoice and the
products are in the system without typing.*

`InvoiceReading` turns a photographed delivery note into lines, and the
confirm screen turns those into stock and a purchase in the books with one
button. Nothing is written before that button. **Arithmetic is what makes it
safe**: a line is `Savon 12 500`, which is either twelve at five hundred or
one at twelve thousand five hundred, and no amount of staring at it settles
that — but a line carrying a total does, because only one reading multiplies
out. Both tokenisations are tried and the checked one wins; where neither
checks, the French reading is used and the line is marked as unverified so it
is the one a person looks at.

Building it caught a real defect in 011, fixed in `016_stock_receipts.sql`:
`receive_products()` passed its `client_uuid` to the ledger and still added to
`products.quantity` unconditionally. A retried delivery counted the goods
twice and the money once, so the shelf and the books disagreed by exactly one
delivery with nothing on any screen to say so. It also closes something 011
claimed and did not do — its header says the quantity column can be rebuilt
from history, which was true of sales and never of deliveries, because stock
arriving was recorded nowhere. `stock_receipts` is what makes that sentence
true.

`015_product_serial.sql` adds the `serial` the plan's product list asks for —
011 built `sku` and called it close enough, which it is not: a SKU names a
kind of thing, a serial identifies one phone — and `product_photos()`, which
reads `documents.product_id` back the other way round so the "photos" in that
same list are reachable from the product.

The two accelerators: barcode scanning at the counter, and on-device OCR.

Scanning finds a product by its code in one tap through `product_by_barcode()`
and, when the shop has never seen the code, says so rather than inventing a
product from a number. It works on both ship targets.

OCR is Android only and reached through a conditional import, so the web build
compiles a stub and never resolves ML Kit. It reads the photograph on the
device: no connection needed, and no picture of anybody's invoice leaves the
phone to be read. What it reads is offered as suggestions and **applied to
nothing** — the rule stated in `013_capture.sql` and asserted from both sides,
because a misread expiry date that silently became `products.expires_on` is
the exact loss this module exists to prevent, with the app's name on it. The
parser errs toward offering nothing: an ambiguous label leaves the box empty,
which costs one person ten seconds instead of costing a shop money for as long
as nobody notices.

**Not verified, and cannot be here:** no Android SDK exists in the environment
this was built in, so the APK has not been compiled and neither the scanner
nor the reader has run on a device. The web build is verified — built, served
and rendered — and the parser has 22 assertions over it, but the plugins
themselves are unproven until somebody installs it on a phone.

---

## M6 — Domains and distribution

> - Deploy workers/tenant-router to Cloudflare and populate the
>   `kaj-tenant-routing` KV namespace (id 87160dd3344245959ab7ca4532cfe169)
>   with hostname → org mappings.
> - Wildcard DNS so every tenant gets `{slug}.marakaj.com` (the vitrine
>   itself lives at `marakaj.com/s/{slug}`).
> - Cloudflare for SaaS for custom domains (`app.theirbusiness.com`).
> - Email domain claim: TXT record verification, then anyone with that email
>   domain auto-joins the org.
> - Play Store release: upload keystore, signed release build, store listing.

---

## Sequencing

M1 first — without it there is no multi-tenant product.
M3 before M4: reports are what make people enter data carefully, and they cost
little once the SQL exists.
M4 and M5 can run in parallel if you bring in another developer.

M1 through M5 are built. What is left is M6 — domains and distribution — and
it is the wrong thing to do next. A week with one real user will reorder the
rest of this list more usefully than any amount of planning, and none of it
has been in anybody's hands yet.

---

## The build order from here (August 2026)

Sequenced by dependency and by what a pilot in Ouagadougou actually needs
next, not by what is most interesting to build. Each block is promptable,
like the milestones above. **M7 gates everything**: nothing below is worth
building on top of an app no real person has used.

### M7 — Production week (operational, small)

> 1. **Done (September 2026):** the live database is at 064 — each new
>    bundle `database/apply_006_to_0NN.sql` is run by the owner in the
>    Supabase SQL editor once, and it is re-runnable. The bundle carries the
>    032 security hardening — critically, the fix that stops any sign-up
>    from making themselves a platform admin — as well as 041 (the platform
>    admin edits the businesses they run), the moderation set (047, 048,
>    049) and 063 (least privilege: the public key runs only the street).
> 1b. **Deferred from 103 (#13), to run once the app that reads
>    `org_private_details()` is live everywhere** (it does from batch 101:
>    `WavePayService.shopWave` and `AdminRepository.orgPlan`; no app read of
>    `orgs` selects `*` or a private column). Until then a member can still
>    read the payout number, the platform's Wave id and the plan note
>    straight from `orgs`. Before running it, check that no SECURITY INVOKER
>    function reads `select * from orgs` or `orgs%rowtype` (definers are
>    unaffected), and remember that every column a later migration adds to
>    `orgs` must then be granted in that migration:
>
>    ```sql
>    revoke select on orgs from authenticated;
>    grant select (id, name, slug, profile, custom_domain, email_domain,
>                  default_currency, created_at, archived_at, archived_by,
>                  address, phone, email, tax_id, tax_label, invoice_footer,
>                  last_activity_at, theme, wave_merchant, suspended_at,
>                  storefront_enabled, storefront_blurb, lat, lng,
>                  delivery_base, delivery_per_km, plan, plan_until,
>                  storefront_style, delivery_max_km, lock_max_minutes,
>                  logo_key, delivery_included_km, referred_by,
>                  progress_since, city, board_hidden, board_notify,
>                  verified_at, verified_by, wave_allowed, setup_done_at,
>                  showcase, photo_slots, association_kind)
>       on orgs to authenticated;
>    -- Kept back: wave_payout_number, wave_merchant_ref, plan_note —
>    -- read through org_private_details() (owner / platform only).
>    notify pgrst, 'reload schema';
>    ```
> 2. **Done:** `UPLOADS_URL` is set in the repo's Actions variables and the
>    build deployed with it. Still to do: put one real photograph through
>    the uploads Worker end to end and confirm `record_document` in the logs.
> 3. Verify email sign-up against the real project with "Confirm email" both
>    on and off; keep whichever setting matches the app's wording.
> 4. Put the app in one real business's hands for a week. Watch
>    `outbox.last_error` in the console daily. Fix what actually breaks, and
>    write down every category name and habit that surprised you.

**Demo after M7:** a stranger recorded a week of real money with no help.

### M8 — The credit book (carnet de crédit)

The single feature that makes a shopkeeper feel the app was built here.
Sales on trust are the daily reality; today the app pretends everything is
cash.

> Migration 024 + screens: a sale or delivery can be "à crédit" against a
> named customer (customers table exists since 020). Records a receivable in
> the existing double-entry machinery — no new ledger concepts. Partial
> repayments. One screen per business: "Qui me doit combien", sorted by age
> of debt, with a repayment button per row. The farm variant covers the
> trader who takes eggs weekly and settles monthly; the church already has
> pledges. SECURITY INVOKER functions, RLS-bound, test suite proving one
> business cannot read another's debtors and that repayments never exceed
> the debt.

**Demo after M8:** Esperance sees who owes her money, oldest first.

### M9 — Customers pay by Mobile Money

> Pick the aggregator (CinetPay first candidate; PayDunya, FedaPay as
> fallbacks — decide on XOF settlement to a BF account, Orange Money BF
> fee, sandbox quality). Payment-link mode only, no in-app SDK: a new
> `workers/payments` Worker creates a link for an invoice and receives the
> signed webhook. Confirmation path: Worker verifies signature → calls
> `record_payment_confirmation()` (SECURITY DEFINER, idempotent by
> aggregator reference) → lands as an ordinary journal entry with the
> reference in `details`. The client never confirms a payment; a payment
> request may queue offline, a confirmation never does. Invoice screen and
> the credit book (M8) both grow a "Payer par Mobile Money" share button —
> the invoice image plus the link is the whole billing loop on WhatsApp.

**Demo after M9:** an invoice is paid from a phone and the books already know.

### M10 — Kaj gets paid: the freemium plan (September 2026)

One person builds this, so it is cut into blocks that each ship alone,
each leaves the app better even if the next never comes, and none of
them waits on a payment aggregator. Money is collected by hand first
and automated only once ten businesses have actually paid — automating
a loop nobody has walked is the most expensive way to learn it was wrong.

**The decision.** Two plans, not three: **Kaj** (free, forever) and
**Kaj Pro** (paid). The line is drawn where a business is visibly making
money with the app, never where it is still deciding whether to trust it.

| Free, forever — the daily habit | Pro — what a grown business needs |
|---|---|
| Stock, sales, returns, expiry alerts | Staff beyond three accounts, shifts and payroll |
| The credit book (qui me doit combien) | The access dial per tool per tier |
| The vitrine, the street, the search, orders, delivery quotes | Analytics: charts, sales by hour and weekday, product performance, losses avoided |
| The shopper pays nothing, ever | Accounting: journal, résultat, bilan, grand livre, balance |
| One owner and up to three staff | Invoices beyond twenty a month |
| Photos, up to fifty per business | History beyond twelve months in reports |
| Contributions and expenses for an association | Multi-currency till and rates; tontines for an association |
| Notifications, in-app and push | |

Lapsing Pro is never a cliff: the business drops back to Free, its Pro
tools become view-only, nothing is deleted, nothing goes read-only that
was free before. Trust is the product.

**Price to test, not to trust:** 2 500 F CFA a month or 25 000 F CFA a
year, paid by Wave or Orange Money to the platform's own number. One
price. Adjust after the first twenty conversations, not before.

#### Block 1 — The plan flag (migration 065, one PR) — **built**

> `orgs.plan` (`free` | `pro`, default `free`), `orgs.plan_until` (date,
> null = no end), `orgs.plan_note`. `set_org_plan(org, plan, until, note)`
> — platform admin only, SECURITY DEFINER like `set_org_suspended`,
> written to the activity log. `org_plan(org)` answers the *effective*
> plan: `pro` while `plan_until` is null or not yet past, `free` after.
> Console: a **Plan** card on the business admin screen (current plan,
> paid until, a form to set it) and a count of Pro businesses on the
> home tiles. Suite: only the platform sets a plan; a past `plan_until`
> reads `free`; the change is in the log.

**Demo after block 1:** you set a business to Pro from the console and
it reads Pro in its settings.

#### Block 2 — The gates (migration 066 + app, one or two PRs) — **built**

> The line lives in `platform_settings`, not in code, so it moves without
> a migration: `pro_features` (a JSON list of tool names), `free_max_staff`
> (3), `free_max_invoices_month` (20), `free_max_photos` (50),
> `free_history_months` (12). `feature_access()` gains one layer *after*
> the owner's dial: on a Free business a tool in `pro_features` answers
> `view`, never `hidden` — the owner keeps seeing the tool, greyed, with
> what it would give them. The caps are enforced where it is cheap and
> matters: `add_employee` and the invoice function raise a code beyond
> the cap; the photo cap is checked in `record_document`. The platform
> admin is never gated. The app draws a small **Pro** badge on gated
> tools and one paywall sheet: what Pro is, the price, the platform's
> Wave number, and a **"J'ai payé"** button that writes a `plan_requests`
> row (org, amount said, when) the console lists. Suite: Free gets `view`
> on a Pro tool and `edit` on everything else; Pro gets `edit`; a lapsed
> Pro reads `view` and loses no row; the fourth staff account is refused
> on Free and accepted on Pro; the dial still wins below the plan (a Pro
> owner can still hide payroll from a clerk).

**Demo after block 2:** a Free business sees Analyses greyed with a Pro
badge, taps it, reads the price, and its "J'ai payé" appears in the
console.

#### Block 3 — The manual money loop (no code)

> An owner pays by Wave to the platform number and taps "J'ai payé". You
> see it in the console, check the Wave app, set the plan Pro for a year.
> Every week, count: businesses active, businesses at a cap, requests,
> conversions. This block ends when ten businesses have paid, or when
> twenty have hit a cap and none paid — which is the signal to move the
> line, not to build more.

**Demo after block 3:** the first franc of recurring revenue, on paper
you can show.

#### Block 4 — The delivery cut (migration 067, one PR) — **built**

> The second stream, and the one that fits the market better than any
> subscription: pay when you earned. `platform_settings.delivery_share`
> (start at 10 %). At order time `orders.platform_fee` is computed from
> the fixed `delivery_fee` and stored beside it; the courier's earnings
> show the net. Until money moves through the platform, the cut is a
> monthly settlement: a console report per courier of fees earned and
> share owed, settled by Wave. Only worth switching on with couriers you
> know personally, or once M9 lets the platform hold the money for a
> moment and keep its share.

**Demo after block 4:** the console says what each courier owes this
month, and the number matches their earnings tally.

#### Block 5 — Automate what block 3 proved (after M9)

> A payment link for Kaj Pro on the paywall sheet; the M9 Worker's
> webhook calls `set_org_plan` with `plan_until` moved a month or a year.
> A push (060) seven days before a lapse, and one on the day. The
> **Revenus** tab of M11: MRR, Free vs Pro, lapses this week — each a
> phone call. `plan_requests` stays for the people who still pay by hand.

**Demo after M10:** a business renews from its phone and the console
knows before you do.

Order for one person: block 1 and 2 are two or three working sessions
and ship before anyone is asked for money; block 3 is calendar time, not
build time; block 4 is one session, when the couriers exist; block 5 is
whenever M9 lands. Nothing here blocks M11 or M12.

### M11 — The platform dashboard grows up

> The console gains tabs, each one server-side aggregate, one round trip:
> **Santé** (existing tiles + 30-day lines: entries/day, new businesses/week,
> businesses going silent/week — you are looking for the bend);
> **Croissance** (funnel: applications → approved → first entry → active at
> 30 days — it says where people are lost); **Revenus** (MRR, paid vs free,
> failed payments this week — each failure is a phone call); **Système**
> (outbox errors platform-wide, app version vs migration state). Every
> number tappable into the list of businesses behind it.

**Demo after M11:** one screen answers "is anything wrong today" in 10 seconds.

### M12 — Languages phase 3

> Extract the remaining deep sheets (recording forms, invoice composer,
> staff, gallery, livestock, console) and everything built since the
> languages milestone — the vitrine, the street and its search, orders,
> the courier's board and map, delivery fees — none of which reads
> `Strings` yet (20 files do; about 130 carry French sentences directly).
> Mechanical, the pattern is established. Commission the Mooré and Dioula reviews of `app_mos.arb` /
> `app_dyu.arb` from paid native speakers — the files are ready and the
> fallback is safe, so enabling each is one line. Server messages move from
> French sentences to error codes the app translates; the migrations keep
> raising codes, `describeError()` maps them.

### M13 — Tontines

> Members, contribution schedule, whose turn, who has paid this round —
> on the existing ledger, per business or standalone group. Design with
> three real tontine organisers before writing SQL; the variants
> (rotating, accumulating, with penalties) differ more than profiles do.

### M14 — Distribution (the old M6, still last on purpose)

> Custom domains, invoice PDF export, QR-scan invitation claiming, the
> member picker on the church sheet, app-store presence. None of it
> creates value until M7–M10 proved somebody wants the thing distributed.

Parallelism: M8 and M11 touch disjoint code and can run side by side. M9
blocks only block 5 of M10 — blocks 1 to 4 collect money by hand first;
M10 blocks the Revenus tab only. M12 can fill any idle week.

## What matters more than any of this

Put the app in Israel's and Ignace's hands and watch them use it. Everything
through M5 is tested against Postgres and against a fake device; almost none of
it has been tested against a person.

One real user for a week will reorder this list more usefully than any amount
of planning. The first thing that week will produce is a list of category and
item names nobody predicted, which is now something the app absorbs rather than
something that has to be shipped — and the second will be a number somebody
reads differently than it was meant. M6 is what is left, and it is
distribution: doing it before anybody has used the thing distributes a guess.
