# Kaj App — Multi-Tenant Business Management Platform

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

### The live site

The **Deploy to Cloudflare** workflow publishes the web build over the `dbms`
Worker:

```
https://dbms.kabore-boss.workers.dev/
```

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

After a deploy, hard-reload. A Flutter web build registers a service worker
that will otherwise serve you the previous bundle from cache.

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

Migrations are applied to Supabase by hand — nothing deploys them. The app and
the database therefore version separately, and the app is the one that moves
first: a deploy can ship screens calling functions the database does not have
yet. That failure looks like this on a phone, and it is not a bug in the app:

> Le serveur a refusé la demande : Could not find the function
> `public.trial_balance(p_from, p_org_id, p_to)` in the schema cache

To bring a database anywhere between `005` and `022` up to date, paste
`database/apply_006_to_022.sql` into the Supabase SQL editor and run it once.
It is `006` through `022` concatenated inside one transaction, so it either
all lands or none of it does, and every migration in it is re-runnable — each
drops what it recreates and creates nothing unconditionally — so running it
against a database that is already part-way through is safe and is the normal
way to use it. It ends with `notify pgrst, 'reload schema'` so PostgREST stops
answering from a stale cache.

Regenerate it after adding a migration, rather than editing it:

```
scripts/build-migration-bundle.sh 006 019
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
