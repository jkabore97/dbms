# Mara — Multi-Tenant Business Management Platform

**Mara** — « Au Service du Peuple » — is the app's name; it is made and
run by Kaj Consulting, which signs the street's footer (« POWERED BY »).
The code keeps its old internal names — the `kaj_app` package, the
Android id `bf.kaj.app` (changing it would orphan every installed phone),
`KajCard`, the `kaj-pay` Worker — and the database's own sentences still
say « Kaj », read as « Mara » by the app (`brandText`) and the push Worker.
Brand files: `app/assets/brand/mara_*`, the icons in `app/web/icons` and
`app/android/.../mipmap-*`; store texts in `docs/brand/mara-store-listing.md`.

One offline-first app for Kaj-consulting's clients — churches, farms, retail shops,
and whatever comes next. Each business is a tenant (`org`) with its own subdomain,
optional custom domain, roles, and modules switched on — same engine underneath.

## Structure

```
database/schema.sql             Postgres schema: tenancy, scoped roles, ledger, RLS
database/migrations/            Profile modules layered on the core schema
database/tests/                 SQL test suite — run by CI on every push
app/                            Flutter app (offline-first, Android/desktop/web)
workers/tenant-router/          Cloudflare Worker: hostname -> tenant lookup via KV
.github/workflows/ci.yml        Runs on every push; validates schema, builds the app once it exists
.env.example                    Required environment variables — copy to .env, never commit .env
```

## Core model

- **orgs → entities → departments**: a business, its locations, their sub-units.
- **memberships** are `(user, role, scope)` — a role is only ever granted at a specific
  scope, so "Manager, Poultry Dept, Farm A" and "Observer, Farm A" (a quieter investor)
  are both first-class, not workarounds.
- **journal_entries / journal_lines**: real double-entry accounting sits under every
  simple button tap. Rows are never edited or deleted — undo is a reversing entry, so
  the audit trail is free and nothing is ever destroyed.
- **documents**: photos and invoices, stored in Cloudflare R2, optionally linked back
  to a ledger entry.

## Setup

1. Create a Supabase project, run `database/schema.sql` against it.
2. Copy `.env.example` to `.env`, fill in the Supabase and Cloudflare values.
3. Enable R2 in the Cloudflare dashboard (one-time manual toggle — API access can't do this step).
4. `flutter pub get` inside `app/` once the Flutter skeleton lands.

## Status

- KV namespace `kaj-tenant-routing` — created, id in `workers/tenant-router/wrangler.toml`.
- R2 — enabled; bucket `kaj-app-uploads` created (region ENAM).
- `workers/tenant-router` — written, not yet deployed (`wrangler deploy`).
- Church module (`002_church_profile.sql`) — built and tested. Contributions,
  expenses, undo-by-reversal, offline idempotency, pastor's weekly summary,
  member giving statements.
- Sync support (`003_sync_support.sql`) — reversal by client_uuid, tested.
- RLS policies (`004_rls_policies.sql`) — every table protected, 22 policies
  here and 26 across the project. Also adds the `my_orgs()` RPC the app calls
  after sign-in, and a trigger that mirrors a new `auth.users` row into
  `profiles` so an invitation has something to point at.
  Cross-tenant isolation proven in `database/tests/test_rls.sql`, which runs as
  the `authenticated` role rather than as postgres — a superuser bypasses RLS,
  so a suite run as postgres would pass against no policies at all. Israel
  cannot see Ignace's books, observers cannot write, and ledger history cannot
  be edited or deleted by anyone.
- Flutter shell (`app/`) — local SQLite with outbox, sync service, church home
  screen, contribution capture. Analyzed clean in CI (`flutter-analyze` job).
- Login and org resolution (M1) — phone + SMS code as the primary sign-in,
  email and password as the fallback. After sign-in the app calls `my_orgs()`:
  one org opens straight into it, several show a picker, none shows a waiting
  screen. The home screen is chosen by the org's `profile` column, so the same
  build shows Israel a church and Ignace a farm. No org id appears anywhere in
  the source.
- Offline re-entry — the identity and org list are cached on the device, and a
  4-digit PIN unlocks the app when the access token has expired and there is no
  signal to refresh it. The PIN is stored only as a salted, stretched hash.
- Invitations (`005_invitations.sql`) — a membership no longer has to be
  inserted by hand. An invitation is a promise of a membership, never a
  membership: `claim_invitation()` is the only path from one to the other, and
  it runs SECURITY DEFINER because the claimer is by definition not yet a
  member and every policy in 004 would deny them. Claiming twice yields one
  membership. Codes are eight characters with `0/O` and `1/I` removed, matched
  through `normalize_invitation_code()` so `chor 2468` and `CHOR-2468` are one
  code. Only an org's admins may read or issue its invitations; a stranger
  holding a code gets `invitation_preview()`, which returns the business name
  and nothing else. 15 assertions in `database/tests/test_invitations.sql`.
- Admin screens — people and their roles, invite by short code or QR, sites and
  departments, and the business's name and currency. None of it is
  offline-first, deliberately: only the server may decide who can see a
  business's books.
- Reports (M3) — the pastor's weekly summary with a share-as-image button,
  cash balances, member giving statements, and a "close the day" ritual with a
  streak. `006_report_access.sql` closed a leak first: `church_account_activity`
  was a view, and a view runs as its owner unless told otherwise, so every
  policy under it was being skipped. The same migration made
  `visibility = 'summary'` mean something for the first time.
- Accounts, not INSERTs — the login screen has a "Créer un compte" side.
  Signing in with a number that has no account is refused and says so, rather
  than silently minting a second account for a mistyped digit. Creating an
  account grants access to nothing; the invitation code, typed on the waiting
  screen or swept up automatically, is still the only path to a membership.
- Everything can be named (`007_accounting.sql`) — `record_entry()` takes the
  words the person typed, and `ensure_account()` turns a name into a real
  account the first time it is used and finds that same account every time
  after. The category chips are now the accounts the books already hold rather
  than seven names compiled into the app, and "Autre…" is a text field. Each
  entry also carries a note and any number of typed characteristics (supplier,
  invoice number, beneficiary) as jsonb. The chart is cached on the device, so
  the real category names are still offered with no signal.
- Accounting (`007_accounting.sql`) — the ledger has been double-entry since
  the first schema and nothing could show it as one. Now: journal, income
  statement, balance sheet, general ledger with a running balance, trial
  balance, an editable chart of accounts, and transfers between cash accounts —
  which stop banking the offering being recorded as earning it twice. 16
  assertions in `database/tests/test_accounting.sql`, the load-bearing one
  being that debits still equal credits once people name their own categories.
- Activity log and console (`008_audit_log.sql`) — the ledger was always its
  own audit trail, which covers money and nothing else; every decision about
  *who may touch* the money was silently mutable. One append-only table, one
  generic trigger over the eight tables that matter, and RLS with a select
  policy and no insert, update or delete policy at all — so the only writer is
  the trigger, which runs outside policy. The console adds a database view
  (every table, its purpose, this org's row count, its columns and foreign
  keys) and a device tab that finally reads `outbox.last_error`, telling
  "waiting for signal" apart from "the server refused this". 10 assertions in
  `database/tests/test_audit.sql`, most of them an owner trying to erase their
  own history.
- Platform admin (`010_platform_admin.sql`) — one boolean on `profiles`,
  `is_platform_admin`, added as a single extra OR clause to each scope helper
  in 004. It answers two things at once: seeing every business without a manual
  membership grant per org, and being able to create one at all. `orgs` has no
  INSERT policy and cannot have a useful one — you cannot be an admin of an org
  that does not exist yet — so `create_org()` runs SECURITY DEFINER and its
  `is_platform_admin` test *is* the authorization, not a backstop. It also
  makes the creator a visible `owner` of the new org and seeds a chart of
  accounts: the church one for `profile = 'church'`, a six-account generic one
  otherwise. 7 assertions in `database/tests/test_platform_admin.sql`, which
  runs as `authenticated` — under postgres, SECURITY DEFINER would hide a
  check that does nothing.
- Ignace's farm (`009_farm_profile.sql`, M4) — the farm counts things as well
  as money, and they are not the same ledger. Items and append-only stock
  movements with a reorder threshold; flocks whose arrival count is never
  edited, so mortality stays visible instead of being overwritten by a running
  total; egg production, which is production and not revenue; customers,
  invoices and part-payments, which need a receivable — the first thing in
  this project that is neither cash nor an expense.

  Recording is offline-first, because Ignace is the user the whole offline
  architecture was built for: feed arriving, feed eaten, birds dying and eggs
  collected all write to the device and drain later. Opening a flock and
  raising an invoice are the two things that need signal, and both for the
  same reason — a batch code and an invoice number have to be unique across
  the business, and two disconnected phones inventing the same one would split
  a cycle's figures in half.

  17 assertions in `database/tests/test_farm.sql`. Most of them test the four
  specific ways a module like this inflates profit: feed expensed twice,
  eggs booked as income before anyone pays, an invoice earned once when raised
  and again when settled, and a dead bird expensed on top of the feed it ate.
- Esperance's store (`011_retail_profile.sql`, M5) — products with a shelf
  price, a cost price, a count and a date they die; sales that move goods and
  money in the same call; and returns, which are sales with `kind = 'return'`
  rather than deletions, so the books show both. Every sale carries a
  `client_uuid` and `record_sale()` returns the original for a repeat, because
  a phone in a market retries and a customer is standing there. The home
  screen leads with what is about to be lost — "3 articles bientôt périmés,
  82 000 en jeu" — since that, not theft or arithmetic, is where the money
  actually goes. 11 assertions in `database/tests/test_retail.sql`, most of
  them the four ways a retail module inflates profit.

  The barcode scanner and the on-device OCR that M5 also asks for are not
  built. `products.barcode`, `documents.ocr_text` and `product_by_barcode()`
  are the seams they attach to; neither can be proven on a runner.
- The payroll (`012_employees.sql`, M5) — permanent and casual staff, shifts,
  and payments that post to the ledger beside rent and stock. Being paid and
  being able to open the books are different things: `employees.user_id` is
  null for most people on a payroll, and adding somebody grants them no access
  at all. Paying a casual settles the shifts it covers in the same
  transaction, which is what stops the same afternoon being paid for twice.
  Reading any of it needs an org admin rather than mere membership — what a
  colleague earns is more sensitive than the takings. 8 assertions in
  `database/tests/test_employees.sql`.
- The camera (`013_capture.sql`, `workers/uploads/`, M5) — the store's primary
  action is now a photograph with **zero required fields**: no category, no
  product, no amount, not a name. The bytes go to the device's own database
  first and to Cloudflare R2 when there is signal, so a picture taken in a
  market with no bars is not lost and is not reported as a failure. Filing it
  is a separate act, done later or never, from the gallery — a photograph that
  stays unfiled forever is the design working.

  `workers/uploads/` is the only thing allowed to write to the bucket and it
  decides nothing itself: it forwards the caller's own token to PostgREST and
  lets RLS answer both "may they upload to this business" and "may they read
  this picture". The bucket has no row-level security of its own, so
  `org/<org_id>/…` is the whole of the tenancy model there, checked on the way
  in and on the way out. 10 assertions in `database/tests/test_capture.sql`,
  most of them one shop reaching for another's photographs; 8 more in
  `app/test/capture_queue_test.dart`, all of them about a photograph surviving
  the app being closed.

  The camera button is drawn only in a build compiled with `UPLOADS_URL`. A
  button that does nothing teaches people the app is broken.
- Barcode and OCR (M5, complete) — scanning a code at the counter finds the
  product in one tap, and says the shop has never seen it rather than
  inventing one from a number. On Android the photograph is also read on the
  device, with no connection and without the picture leaving the phone, and
  what it read is offered as **suggestions that are never applied**: nothing
  in the schema reads `ocr_text`, and a misread expiry date that silently
  became `products.expires_on` is the exact loss this module exists to
  prevent. 22 assertions in `app/test/reading_suggestions_test.dart`, most of
  them about offering nothing rather than guessing — an ambiguous label leaves
  the box empty.

  ML Kit has no web implementation and will not get one, so it is reached
  through a conditional import: the browser build compiles a stub and never
  resolves the package. The barcode scanner needs no such split — it works on
  both ship targets.
- The lifecycle of a business (`014_org_lifecycle.sql`, `Entreprises`) — a
  platform admin can now rename one, change its address, its type or its
  currency, put it away, and destroy it. Archiving is the ordinary way to make
  a business go away: reversible, keeps every entry, and off every member's
  home screen. Deleting is the one act in this schema that loses data on
  purpose, and it is fenced four ways — platform admin only, archived first,
  the name typed back, and a second explicit act when the books are not empty.

  A deleted business leaves a tombstone in `deleted_orgs`, which is not
  org-scoped and which nothing may write to or delete from. That table exists
  because `audit_log.org_id` cascades: without it, the one event in this
  system that erases a business would also erase its own record. 19 assertions
  in `database/tests/test_org_lifecycle.sql`, plus 6 in
  `app/test/delete_business_test.dart` about the dialog being hard enough to
  press.
- A photographed delivery becoming stock (`015`, `016`, M5's demo) — the
  invoice reader turns a delivery note into lines, and one button turns those
  into products, stock and a purchase in the books. Arithmetic decides what
  each number is: `Savon 12 500` is ambiguous until a total is present to
  multiply into, so both readings are tried and the one that checks wins.
  Nothing is written before the button, and a line that did not check out is
  marked rather than hidden.

  Building it caught a real defect in 011. `receive_products()` deduplicated
  its ledger entry by `client_uuid` and still added to `products.quantity`
  unconditionally, so a retried delivery counted the goods twice and the money
  once — the shelf and the books disagreeing by one delivery, silently.
  `016_stock_receipts.sql` fixes it and gives deliveries the append-only
  history that 011's own header claimed they already had.
- Two ways into the app (`017`, M6) — an employee makes an account, says who
  they are (first, middle and family name, date of birth, job title, phone
  typed twice), and enters the code their manager sent. **Filling in the form
  grants nothing**; the code does, and the suite asserts it. A manager does
  the same and then *asks* for a business: `create_org()` stays platform-admin
  only, `org_applications` is the queue that decision is made from, and
  approving creates the business and makes the applicant its **owner** in one
  transaction.

  "J'ai un code" is gone. It sat with the invitee, who by definition does not
  have the app yet. In its place is a generator on the manager's side that
  composes the message and sends it to WhatsApp, with a QR for the case where
  the new employee is standing right there. 17 assertions in
  `database/tests/test_onboarding.sql`.

  This surfaced a collision: 005 pinned invitations to `auth.users.phone`, and
  017 lets somebody set a different profile number — which is the one they
  give their manager. A manager typing it would have produced a code that
  could never be claimed. Both matchers now accept either of a person's own
  numbers; it is still a pin.
- Staff records every business can use (`018`) — where somebody works, what
  kind of engagement it is, and why they left. `volunteer` is the one that
  matters most: recording a church's unpaid caretaker as a casual on zero
  francs makes the payroll say something untrue about what the church owes.
  `end_employment()` refuses while wages are outstanding, because unpaid hours
  that leave the screen are unpaid hours nobody pays. The Personnel screen is
  now reachable from the church and the farm, not only the shop.
- A farm that is not only chickens (`019`) — herds of any species, crop cycles
  on plots, and harvests. 009 built Ignace's poultry farm and nothing else had
  a table; a farmer with goats and onions was expected to record animals as a
  flock with a batch code and a harvest as "other income". `flocks` is
  untouched and unmigrated — his history is in it — and the home screen leads
  with whichever a farm actually has.

  A harvest posts nothing to the ledger. Bringing a crop in is not earning
  money, it is earning it later or eating it, and booking income there
  inflates the income statement by every sack that never reached a market.
  11 assertions in `database/tests/test_farm_general.sql`.
- Next: M6 — custom domains, the tenant router, and a Play Store release. Also
  still open: reading an invitation QR with the camera, rather than the
  invitee typing the code.

## Cloud development (recommended)

This repo is configured for GitHub Codespaces, so nothing needs installing
locally. On the repo page: **Code -> Codespaces -> Create codespace on main**.

The first build takes about 5 minutes and installs Flutter, the Postgres
client, wrangler, and Claude Code. After that it starts in seconds and the
machine persists between sessions.

Free tier is roughly 60 core-hours/month on a personal account — about 15
hours on the 4-core machine configured here. Stop the Codespace when you
are done; it does not bill while stopped.

Secrets go in Codespaces secrets (github.com/settings/codespaces), never in
files. They appear as environment variables inside the Codespace.

Codespaces secrets and Actions secrets are two separate stores: setting one
does not set the other. The Codespace reads `SUPABASE_URL` and
`SUPABASE_PUBLISHABLE_KEY` (or `SUPABASE_ANON_KEY`) from the first, the build
workflows read them from the second.

To run the app from a Codespace:

```
cd app && ./scripts/serve.sh
```

It compiles the credentials in and serves on port 8080, which Codespaces
forwards — VS Code offers the https URL, and setting that port to **Public**
makes it reachable from a phone. Run `flutter run -d web-server` directly and
you get a build with no server address in it, which opens on *Serveur non
configuré*; the credentials are compiled in, never read at runtime.

## Running the app

```
cd app
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=your-publishable-key
```

Credentials are passed at build time, never committed.

### Builds from GitHub Actions

The **Build App** workflow compiles the same two `--dart-define` values into the
APK and the web bundle, reading them from repository secrets. Set them once
under **Settings → Secrets and variables → Actions**:

| Secret | Value |
| --- | --- |
| `SUPABASE_URL` | `https://YOUR-PROJECT.supabase.co` |
| `SUPABASE_PUBLISHABLE_KEY` | the project's publishable (formerly anon) key |

They must be **repository** secrets under the **Actions** tab. Secrets stored
under Codespaces, Dependabot, or a named Actions environment are invisible to
these jobs. `SUPABASE_ANON_KEY` is accepted for the key as well, since that is
what the Supabase dashboard still labels it.

Both jobs stop with a "missing repository secret" error rather than upload an
installable that cannot sign anyone in. If a build you downloaded shows
*Serveur non configuré* on the login screen, the secrets were not set when it
ran — add them and re-run the workflow, then reinstall the artifact.

The publishable key is designed to ship inside clients; RLS is what protects
the data. The service_role key never goes into a build.

### Signing the Android app

The app's identity on a phone is `bf.kaj.app`. A release build is signed
with an *upload key* that lives in exactly two places: the keystore file
on the machine that made it, and four repository Actions secrets. It is
never committed, never pasted anywhere — a leaked upload key cannot be
rotated on a published app.

Make it once, on your own computer (Java's `keytool` ships with Android
Studio and with any JDK):

    keytool -genkey -v -keystore upload-keystore.jks -storetype JKS \
      -keyalg RSA -keysize 2048 -validity 10000 -alias upload

Answer the prompts (the passwords are yours to choose and keep), then set
these under Settings > Secrets and variables > Actions > Repository secrets:

    KAJ_KEYSTORE_BASE64      base64 -w0 upload-keystore.jks   (one line)
    KAJ_KEYSTORE_PASSWORD    the keystore password you chose
    KAJ_KEY_ALIAS            upload
    KAJ_KEY_PASSWORD         the key password you chose

Keep `upload-keystore.jks` somewhere safe and backed up. From then on the
"Build App" workflow produces a signed `app-release.apk` (installable on
any phone) and `app-release.aab` (what the Play Console takes). Without the
secrets it still builds, signed with the debug key — fine for testing on a
phone, refused by the store, and the run's summary says which one you got.

### Publishing to Google Play

Once set up, nobody uploads an `.aab` by hand: every push to `main` builds
the bundle, signs it with the upload key and sends it to Google Play
("Send to Google Play" in *Build App*). The version code is the run
number, so each one is newer than the last. Google reviews each update
(usually a few hours) and phones update themselves. The Play copy never
shows the « Télécharger » banner (it is built with `STORE=play`): the store
brings its updates, and the GitHub APK, signed by a different key once Play
App Signing holds the app's key, would not install over it.

Once:

1. The upload key secrets ("Signing the Android app" above).
2. In the Play Console, create the app (package `bf.kaj.app`), and upload
   the **first** `kaj.aab` by hand to *Testing › Internal testing*, then roll it
   out. Google accepts the API only after that first one. Take it from the
   latest GitHub release.
3. In Google Cloud (any project, e.g. the Firebase one): *IAM › Service
   accounts › Create*, no roles; then *Keys › Add key › JSON*. Enable the
   **Google Play Android Developer API** on that project.
4. In the Play Console: *Users and permissions › Invite new users*, the
   service account's e-mail, app `bf.kaj.app`, with *Release to production,
   exclude devices, and use Play App Signing* and *Release apps to testing
   tracks*.
5. Repository secret `PLAY_SERVICE_ACCOUNT_JSON` = the whole JSON file.

Repository variables (optional): `PLAY_TRACK` — `internal` by default;
`alpha` for closed testing, `production` once the store listing is
approved. `PLAY_STATUS` — `completed` by default; `draft` leaves each
release for a person to roll out in the Console.

Without `PLAY_SERVICE_ACCOUNT_JSON` the bundle is only attached to the
GitHub release, and the run's summary says so.

### Installing and updating the Android app

The web app is whatever was deployed last, every time it loads. A phone is
whatever APK was installed the day it was installed — and for a while
nothing told it a newer one existed, so every fix shipped only reached the
phones somebody reinstalled by hand. Two things close that gap:

- **A public download link.** Every push to `main` builds the app and
  publishes it as a GitHub release marked *latest*, so this address is
  always the newest build:

      https://github.com/jkabore97/dbms/releases/latest/download/kaj-arm64-v8a.apk

  That is the file for nearly every phone. `kaj-armeabi-v7a.apk` on the
  same release is for older 32-bit phones; `kaj.aab` is what the Play
  Console takes. Send the link on WhatsApp; the phone downloads and
  installs over the old version, keeping its data.

- **The app knows when it is old.** Every build carries the commit it was
  made from (`--dart-define=BUILD_SHA`), and the web deploy writes the
  deployed commit into `version.json` beside the app. The app looks once at
  start and every six hours; when the two differ, a banner says so and
  offers the download on a phone, or a reload in a browser tab that has
  been open since before a deploy.

The APK is one per processor (`--split-per-abi`) and shrunk by R8, which is
roughly half of what the single all-architectures package weighed; the
run's summary prints the sizes. A manual run of "Build App" on a branch
builds without publishing; on main it publishes a new release, like a push
— the way to remake the APK after adding a secret.

### Crash reporting

An error in production used to be invisible unless a user described it.
The app now reports uncaught errors to Sentry — stack traces only, no
personal data, no performance traces — when a build carries a DSN:

1. Create a free project at sentry.io (platform: Flutter) and copy its DSN.
2. Set `SENTRY_DSN` as a repository Actions *variable* (it is public by
   design: it ships in every client and can only send).

Both "Deploy to Cloudflare" and "Build App" pass it as
`--dart-define=SENTRY_DSN`. Without it the reporter is a no-op, so local
builds and forks report nothing anywhere.

### Push notifications

The bell (030) rings inside the app, live (115: Realtime on `notifications`,
under its row security — each phone hears its own rows — plus a return to
the app and a one-minute poll), and with this set up it also reaches a
**closed** app: in a browser by Web Push (Chrome and Firefox on Android and
desktop; Safari from iOS 16.4 when the site is added to the home screen),
on the Android app by Firebase Cloud Messaging. The pieces: migrations 060
and 115 (the address book, `push_subscriptions`, browsers and phones — on an
older database, applied with `database/apply_006_to_121.sql`, below),
`workers/push` (the sender: Web Push and FCM HTTP v1), `web/push_handlers.js`
(the browser's receiver, carried by `web/mara_sw.js` — or by the bare
`web/push_sw.js` where no worker holds the site yet), and a database webhook
that wakes the Worker on every bell row.

One-time setup, in this order:

1. **The site's push identity**, in a Codespace, once — never again (a new
   pair silently orphans every subscriber):

       node workers/push/scripts/make-vapid.mjs

   Store the public line as the repository *variable* `VAPID_PUBLIC_KEY`
   and the private line as the repository *secret* `VAPID_PRIVATE_KEY`.
2. **Two more secrets.** `SUPABASE_SERVICE_ROLE_KEY` (Supabase → Project
   Settings → API — the push Worker is the only component that holds it,
   and it uses it for push_devices / push_targets / remove_push_target,
   granted to that role alone) and `PUSH_WEBHOOK_SECRET` (any long random
   string, e.g. `openssl rand -hex 32`).
3. **Deploy the Worker**: the "Deploy the push Worker" workflow. Its summary
   prints the Worker's origin.
4. **`PUSH_URL`**: set that origin as the repository variable `PUSH_URL` and
   re-run *Deploy to Cloudflare* (and the APK build) — the web app then
   offers « Activer » on every home of the three kinds, the shopper's
   profile, the courier's space and the command center's Réglages, and
   quietly writes back a browser that had already said yes.
5. **The webhook.** Supabase → Database → Webhooks → Create: table
   `notifications`, event `INSERT`, HTTP `POST` to `<PUSH_URL>/v1/notify`,
   HTTP header `Authorization: Bearer <PUSH_WEBHOOK_SECRET>`.
6. **Android (optional).** In the Firebase console: a project, an Android
   app with the id `bf.kaj.app`; download its `google-services.json` and
   put the whole file in the repository *secret* `GOOGLE_SERVICES_JSON`
   (the APK build writes it to `app/android/app/`, gitignored — the Gradle
   plugin is applied only when the file is there, so a build without it
   still succeeds and simply offers no Android push). Then Project settings
   → Service accounts → Generate new private key: put that JSON in the
   repository *secret* `FCM_SERVICE_ACCOUNT` and re-run "Deploy the push
   Worker" (without it the Worker skips phones and rings browsers).
   **Then install an APK built after the secret was set**: a push to main,
   or "Run workflow" on *Build App* from main, publishes a new release
   (the build's summary says « google-services.json installed »). An APK
   from before has no Firebase in it and never registers — the
   diagnostics below then say « Firebase démarré : non ».
7. **Check it**: Compte › Notifications › « M'envoyer une notification
   test » (anyone), or the command center's Réglages › « Tester la
   notification », which also says how many devices the account has and
   whether the webhook of step 5 exists. Under both, « Diagnostic de cet
   appareil » shows each step on THIS device — Firebase started, the
   permission, the token or the browser's subscription, saved on the
   server — with « Réessayer l'enregistrement ».

Until every step is done nothing rings with the app closed — and nothing
breaks: the app offers no push without a `PUSH_URL` (or, on Android,
without Firebase), the Worker answers a wrong secret with 401, and the bell
inside the app works throughout.

### Wave checkout

Orders, Kaj Pro and spots paid by Wave — or by card on Wave's own page —
and each shop paid on its own Wave number a moment later (migration 076,
`workers/pay`). Kaj holds one Wave Business account registered as an
**aggregator**; the shops need only an ordinary Wave number.

How a payment goes: the app asks the kaj-pay Worker (with the person's own
sign-in) → `wave_begin()` checks the order, plan or spot is theirs to pay
and fixes the amount → the Worker opens a Wave checkout session → the
person pays in Wave (or by card on Wave's page) → Wave posts a signed
webhook to `<PAY_URL>/v1/wave` → `wave_settle()` marks it paid (Pro and
spots switch themselves on) → for an order the Worker sends the goods'
price, less the platform's share, to the shop's number through Wave's
Payout API, the payment id as the idempotency key; failed payouts are
retried every 15 minutes, five times, and shown in the console.

One-time setup, in order:

1. **Wave Business for Kaj in Burkina Faso** (a registered company: RCCM,
   IFU). Ask Wave for API access with **Checkout**, **Payout** and
   **Aggregated Merchants**, and to be registered as an aggregator.
2. **The keys.** In the Wave Business portal → Developers: create an API
   key with those scopes, and a webhook to `<PAY_URL>/v1/wave` for
   `checkout.session.completed` and `checkout.session.payment_failed`.
   Put the key in the repository secret `WAVE_API_KEY` and the webhook
   secret in `WAVE_WEBHOOK_SECRET` — never in chat. (`SUPABASE_SERVICE_ROLE_KEY`
   is already there for the push Worker.)
3. **Deploy**: the "Deploy the payments Worker" workflow. Set the repository
   variable `PAY_URL` to its origin and re-run *Deploy to Cloudflare*.
4. **Each shop**: Paramètres › Paiements › « Numéro Wave » (the shop's
   own). For each shop Wave registers as an aggregated merchant, put the id
   Wave gives in Paramètres › Formule et modération (platform only).
5. **Try it**: a 100 F order to your own shop, paid from your phone. Then
   Console › Paiements Wave: switch « Paiement Wave dans Kaj » on — and
   « Payer par carte » only once Wave's page takes cards for the account.
   Set the platform's share there (0 % by default).

Until step 5 nothing changes for anyone: the shop's own Wave link and
« J'ai payé » stay as they are.

### Kaj Pro by card (Stripe)

Kaj Pro as a monthly or yearly **card subscription** through Stripe
(migration 082, `workers/pay/src/stripe.js`). Stripe is used for the
subscription only; orders are still paid by Wave. **The price is yours:**
Console › Kaj Pro › « Prix par mois » / « Prix par an », the same fields
the Wave payment reads, so the comparison page, Wave and Stripe all charge
the same amount. The Worker sends that price to Stripe on each new
checkout, so there is no Stripe product to keep up to date. A new price
applies to **new** subscriptions; a running one renews at the price it
started with (Stripe's rule).

How it goes: on `/o/<id>/kaj-pro` an admin taps « S'abonner par carte » →
the Worker calls `stripe_begin()` with the owner's own sign-in (admins only;
the amount comes from the database) → Stripe Checkout, in French → Stripe
posts a signed webhook to `<PAY_URL>/v1/stripe` → the Worker reads the
subscription again from Stripe and calls `stripe_settle()` (service role
only) → the business is Pro until the end of the paid period plus one day.
Renewals move that date forward. A cancellation keeps what was already paid.
A longer date bought with Wave, or a Pro with no end date (a gift), is never
shortened. « Gérer la carte ou annuler » opens Stripe's own customer page.

One-time setup (keys go only in GitHub's secrets page, never in chat):

1. **Stripe account** for Kaj, activated for live payments. Since 121 the
   card is **charged in US dollars** (Mara's account is in the US) while
   every price the app shows stays in FCFA: the database converts the
   FCFA price at Command center › Réglages › Mara Pro « Taux pour la
   carte : FCFA pour 1 $ » (`stripe_xof_per_usd`, seeded 600; a whole
   number above zero), rounded up to the cent. Stripe's page names the
   FCFA price (« Mara Pro · Mensuel · 15 000 FCFA · <business> ») and the
   app shows « ≈ $25.00 par mois, payé en dollars » under the button. A
   new rate applies to new subscriptions, as a new price does.
2. **Settings › Billing › Customer portal**: switch on cancelling and
   updating the payment method, then save. The « Gérer » button opens this
   page.
3. **Developers › API keys**: put the secret key in the repository secret
   `STRIPE_SECRET_KEY`.
4. **Developers › Webhooks** › Add endpoint `<PAY_URL>/v1/stripe`, with
   events `checkout.session.completed`, `invoice.paid`,
   `invoice.payment_failed`, `customer.subscription.updated` and
   `customer.subscription.deleted`. Put its signing secret in
   `STRIPE_WEBHOOK_SECRET`.
5. **Deploy**: run the "Deploy the payments Worker" workflow. Either Stripe
   or Wave alone is enough to deploy it. Make sure `PAY_URL` is set, then
   re-run *Deploy to Cloudflare*.
6. **Switch it on**: Console › Kaj Pro › « Abonnement par carte (Stripe) ».
   Try it first with a test key (`sk_test_…`) and the card 4242 4242 4242
   4242, then swap in the live key.

Until step 6, no card button appears anywhere.

### Google sign-in

« Continuer avec Google » sits above the e-mail form, for signing in and
signing up alike, and appears only once the project has Google switched on —
the app asks `/auth/v1/settings` and draws nothing otherwise. Google says who
the person is (an account is created on the first visit, named from Google;
an existing account with the same verified e-mail is the same account), and
then the device code is chosen exactly as after a password. From there on,
the code is all anyone types.

To switch it on (owner, once — no secret goes in the repository or in chat):

1. **Google Cloud Console** → APIs & Services → OAuth consent screen: app
   name « Kaj », support e-mail, the live site as authorised domain;
   publish it (External).
2. Credentials → Create OAuth client ID → **Web application**. Authorised
   redirect URI: `https://dkrtntrcbhuuouctfyug.supabase.co/auth/v1/callback`.
   Keep the client ID and secret.
3. **Supabase dashboard** → Authentication → Providers → Google: on, paste
   the client ID and secret, save.
4. Authentication → URL Configuration → Redirect URLs, add both:
   `https://marakaj.com/**`, `https://www.marakaj.com/**`,
   `https://dbms.kabore-boss.workers.dev/**` (the web app comes back to
   `/connexion`) and `bf.kaj.app://login-callback` (the Android app; the
   intent filter in `AndroidManifest.xml` catches it).
5. Open the live site signed out: the button is there. On Android, Google
   opens in the browser and hands back to the app.

### What only the owner can switch on

Three things the code is ready for and that need the owner's own accounts.
None is pasted anywhere but GitHub's secrets page.

1. **Crash reports** — create a Sentry project (Flutter), copy its DSN into
   the repository variable `SENTRY_DSN`, re-run *Deploy to Cloudflare*.
   Five minutes; the app then reports crashes and slow screens.
2. **The Play Store** — make the upload key once (`keytool -genkey -v
   -keystore kaj-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias
   kaj`), keep the file and both passwords somewhere safe, and set the four
   secrets `KAJ_KEYSTORE_BASE64` (`base64 -w0 kaj-upload.jks`),
   `KAJ_KEYSTORE_PASSWORD`, `KAJ_KEY_ALIAS` (`kaj`) and `KAJ_KEY_PASSWORD`
   ("Signing the Android app" above). The next *build-android* run produces
   a release-signed `.aab`; upload it in the Play Console to the **internal
   testing** track first (one-time 25 USD developer account, store listing,
   privacy policy URL — the site's `/confidentialite` page).
3. **Alerts on a closed Android app** — create a Firebase project, add an
   Android app with the package name `bf.kaj.app`, and
   put `google-services.json` in the repository secret
   `GOOGLE_SERVICES_JSON` — the file's raw content, pasted as it is (not
   base64), and never in chat. Firebase Cloud Messaging is wired into the
   app and the push Worker since 115 ("Push notifications", step 6).

### The live site

The **Deploy to Cloudflare** workflow publishes the web build over the `dbms`
Worker:

```
https://marakaj.com/
https://dbms.kabore-boss.workers.dev/
```

marakaj.com is a Custom Domain of the `dbms` Worker, attached once in the
Cloudflare dashboard (Workers & Pages → dbms → Settings → Domains & Routes →
Add → Custom Domain: `marakaj.com`, then `www.marakaj.com`). The Android app
and every shared vitrine link point there (`app/lib/core/site/site.dart`;
`--dart-define=SITE_URL=…` overrides it). Supabase's Site URL is
`https://marakaj.com`.

It needs one repository secret, `CLOUDFLARE_API_TOKEN`, with the *Edit
Cloudflare Workers* permission ([create one
here](https://dash.cloudflare.com/profile/api-tokens)). Nothing has to be
switched on in a settings page — the token is the whole authorisation.

`workers/kaj-app/wrangler.toml` is assets-only: there is no `main`, because
the app needs no server-side logic to decide which business it shows — the org
comes from the signed-in user's memberships, never from the hostname. The
Worker's name is `dbms` deliberately, matching the hostname already in use; a
different name would publish to a URL nobody is looking at and leave that one
serving whatever it served before.

After a deploy there is nothing to clear by hand. The deploy gives every
file that changes between builds a folder named after its content
(`scripts/web-fingerprint.mjs`: `/app/<hash>/`, `/ck/<hash>/`, `/a/<hash>/`,
kept a year by the site Worker) and writes the build into `web/mara_sw.js`,
the service worker every visitor gets. A phone that already keeps Mara opens
the build it has at once — on a slow line or with none — prepares the new
one in the background, and switches at its next start, or straight away
from « Recharger » on the update banner. A first visit always gets the
build just deployed.

### Testing it in a browser

Open the Cloudflare URL above. It is public, like any hosted app: the
publishable key is compiled into it by design and RLS is what protects the
data, so signing in still requires a Supabase user with a membership row.

There was a second workflow, **Deploy Web**, publishing the same build to
GitHub Pages at `jkabore97.github.io/dbms/`. It is deleted. It failed on every
run from the day it was written — `actions/configure-pages` with
`enablement: true` asks GitHub to switch Pages on through the API, and GitHub
refuses that to a workflow token ("Resource not accessible by integration").
Only a repository admin can flip it, at **Settings → Pages → Source: GitHub
Actions**.

Once Cloudflare was serving the app there was nothing left for it to do but
publish a second copy, to a second URL, and fail loudly on every push. If a
Pages mirror is ever wanted, turn the setting on by hand first and restore the
file from git history — the build steps in it were correct, and only the
enablement was ever the problem.

Signing in needs those values: without them there is no server to authenticate
against and the login screen says so. Once a user has signed in on a device and
chosen a PIN, that device keeps working with no connection at all — that is
what the offline path is for.

Phone sign-in also needs an SMS provider configured under Authentication →
Providers → Phone in the Supabase dashboard. Until that is set up, use the
email and password fallback on the login screen.

A person who signs in but belongs to no org sees the waiting screen. To let
them in, insert a membership:

```sql
insert into memberships (org_id, user_id, role, scope_kind, scope_id)
values ('<org id>', '<their auth.users id>', 'admin', 'org', '<org id>');
```

## Publishing the app on Cloudflare

The web build is served as an assets-only Worker — no server code, because the
app never needs the server to decide which business it is showing. The org
comes from the signed-in user's memberships, so one bundle serves every tenant.

```
wrangler login                                          # once, opens a browser
scripts/build-web.sh                                    # reads .env, compiles credentials in
wrangler deploy --config workers/kaj-app/wrangler.toml
```

That publishes to `kaj-app.<your-subdomain>.workers.dev`, which is the URL to
test on before any DNS exists. `scripts/build-web.sh` refuses to run without
`SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` in `.env`, because a bundle built
without them deploys perfectly and then cannot sign anybody in.

Deep links work on reload: `not_found_handling = "single-page-application"`
sends unknown paths to `index.html`, where Dart resolves the route.

To put a tenant on its own hostname, add the custom domain to the `kaj-app`
Worker in the Cloudflare dashboard (Workers → kaj-app → Settings → Domains &
Routes). Nothing in the bundle changes — the same assets answer on every
hostname. `workers/tenant-router` is a separate Worker for a separate job:
attaching tenant headers for server-side callers such as a Supabase Edge
Function. Hosting the app does not depend on it.

## The upload Worker

Photographs do not go to Supabase. They go to the R2 bucket `kaj-app-uploads`,
through `workers/uploads`, which is the only thing in this repository allowed
to write there.

It is a Worker rather than a pre-signed URL for one reason: signing still needs
something to decide *who may have a URL*, and once that exists the signing buys
nothing but a second moving part holding a key. So the Worker holds the R2
binding and never hands it out.

**It decides nothing itself.** Every authorisation question is forwarded to
Postgres and answered by the same RLS policies that guard the tables — it asks
"may this token see this org?" by doing the select *as that token* and looking
at whether a row comes back, and "may they see this picture?" by selecting the
`documents` row for that key the same way. It holds no service-role key, so
there is nothing in it that could answer wrongly and be believed.

The bucket has no row-level security of its own. `org/<org_id>/…` is the whole
of the tenancy model there, checked on the way in and on the way out.

```
wrangler deploy --config workers/uploads/wrangler.toml \
  --var "SUPABASE_URL:$SUPABASE_URL" \
  --var "SUPABASE_PUBLISHABLE_KEY:$SUPABASE_PUBLISHABLE_KEY"
```

The API token needs **Workers R2 Storage: Edit** on top of Workers Scripts:
Edit — which is why *Deploy the upload Worker* is a separate workflow from
*Deploy to Cloudflare*: a token that cannot bind R2 must not be able to stop
the app itself going out.

Then set the repository **variable** `UPLOADS_URL` to that Worker's origin and
re-run *Deploy to Cloudflare*. Until it is set the camera button is not drawn
at all — a button that does nothing teaches people the app is broken — and
`ALLOWED_ORIGINS` in `workers/uploads/wrangler.toml` has to name the site
calling it, because the endpoint answers differently per caller and a wildcard
there would let any page a signed-in person opens read their photographs.

## Keeping the live database up to date

**By CI, once one secret is set.** The *Apply migrations* workflow
(`.github/workflows/migrate.yml`) runs `scripts/apply-migrations.sh` on every
push to `main` that touches `database/migrations/`: each migration the live
database has not had runs in its own transaction, and lands with its row in
`kaj_migrations` or not at all. It stays dormant — green, with a notice —
until the repository secret `SUPABASE_DB_URL` exists (Supabase → Project
Settings → Database → Connection string → URI, session pooler, password
filled in). The live ledger is already seeded through the last migration
applied by hand, so the first run applies only what is new.

Until then, migrations are applied by hand, and the app and the database
version separately. The app is the one that moves first: a deploy can ship
screens calling functions the database does not have yet. That failure looks
like this on a phone, and it is not a bug in the app:

> Le serveur a refusé la demande : Could not find the function
> `public.trial_balance(p_from, p_org_id, p_to)` in the schema cache

To bring a database anywhere between `005` and `121` up to date, paste
`database/apply_006_to_121.sql` into the Supabase SQL editor and run it once.
It is `006` through `121` concatenated (114, 116 and 120 are unused numbers) inside one transaction, so it either
all lands or none of it does, and every migration in it is re-runnable — each
drops what it recreates and creates nothing unconditionally — so running it
against a database that is already part-way through is safe and is the normal
way to use it. It ends with `notify pgrst, 'reload schema'` so PostgREST stops
answering from a stale cache.

Regenerate it after adding a migration, rather than editing it:

```
scripts/build-migration-bundle.sh 006 119
```

Verified by building a database at `005`, running the bundle, and re-running
every suite in `database/tests/` against the result.

To make an account a platform admin — able to see every business and create
new ones — after that account has signed up at least once:

```sql
update profiles set is_platform_admin = true
where id = (select id from auth.users where email = 'you@example.com');
```

## Running the tests locally

```
createdb kajtest
psql -d kajtest -v ON_ERROR_STOP=1 -f database/tests/supabase_stub.sql
psql -d kajtest -v ON_ERROR_STOP=1 -f database/schema.sql
for f in database/migrations/*.sql; do
  psql -d kajtest -v ON_ERROR_STOP=1 -f "$f"
done
for t in church rls invitations reports accounting audit farm; do
  psql -d kajtest -v ON_ERROR_STOP=1 -f "database/tests/test_$t.sql"
done
```

Every suite seeds its own rows and none of them is idempotent — drop and
recreate `kajtest` between runs. Run them in the order above: the later ones
read rows the earlier ones committed.

`test_church.sql` prints values and expects several of its statements to fail —
those `ERROR:` lines are the rejections it is asserting. The other six print
`PASS:` per assertion and abort on the first failure — 79 assertions in total.

All but `test_church.sql` run as the `authenticated` role with a JWT subject
set, never as postgres. A superuser bypasses RLS, so a suite run as postgres
would pass against no policies at all — and every recording function from 007
onwards additionally refuses a caller with no `auth.uid()`, so a suite run as
postgres could not even record anything to assert about.

The Flutter tests need no database or network:

```
cd app && flutter test
```

`supabase_stub.sql` fakes the `auth.users` table and `auth.uid()` that Supabase
provides, so the schema can be tested on plain Postgres. Never run it against
a real Supabase database.

## Security

No live key, token, or service-account file belongs in this repo or in any chat.
Secrets go in GitHub Actions secrets and Cloudflare Worker secrets only.

**What the public key can run.** Since `063`, a SECURITY DEFINER function
is executable by `anon` only if it is part of the street — the storefront
readers, `search_products`, `delivery_quote`, `storefront_photo_allowed`
(the uploads Worker's check) and `invitation_preview` — or one of the six
helpers RLS policies call (`is_org_member`, `is_org_admin`, `can_write_org`,
`has_full_visibility`, `feature_access`, `my_org_ids`), which must run as
any caller for a policy to answer at all. Everything else is refused by
the database before the function runs, and a function created after
`063` is born that way: the default privileges no longer grant `anon` or
`PUBLIC`. A new function meant for the street must say so with an explicit
`grant execute … to anon`, and `database/tests/test_least_privilege.sql`
will fail if a policy starts calling a helper that is not on the list.
Supabase's security advisor (Dashboard → Advisors) is the place to check
this holds after a migration.

**Two steps for the platform admin — optional, off.** `077` built a
second step for the platform admin: the password *and* a six-digit code
from an authenticator app (Google Authenticator, Microsoft Authenticator),
enforced by the database — `two_step_gate()` is PostgREST's pre-request
hook, and with the switch on, a platform admin's token below `aal2` is
refused on every request but `my_two_step()`. Since `078` it is **off by
default**: every account, the platform's included, signs in with the
password once and the device code after. The platform admin switches it on
in Compte › Sécurité › Plateforme; Kaj then shows how to add the app, and
asks the code once per sign-in. Switching it off again needs the code.
Shops and shoppers are never asked. **Lost the phone with it on:**
Supabase SQL editor → `update platform_settings set value = 'false' where
key = 'admin_two_step';` (or delete the account's MFA factor under
Authentication → Users).
