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
- Next: Esperance's store (M5) — capture-first, photo to R2, on-device OCR —
  and a camera scanner so a QR can be read as well as shown; today the invitee
  types the code.

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
switched on in a settings page — the token is the whole authorisation, which
is the practical difference from Pages below.

`workers/kaj-app/wrangler.toml` is assets-only: there is no `main`, because
the app needs no server-side logic to decide which business it shows — the org
comes from the signed-in user's memberships, never from the hostname. The
Worker's name is `dbms` deliberately, matching the hostname already in use; a
different name would publish to a URL nobody is looking at and leave that one
serving whatever it served before.

After a deploy, hard-reload. A Flutter web build registers a service worker
that will otherwise serve you the previous bundle from cache.

### Testing it in a browser

The **Deploy Web** workflow publishes the web build to GitHub Pages:

```
https://jkabore97.github.io/dbms/
```

It needs Pages switched on once: **Settings → Pages → Build and deployment →
Source: GitHub Actions**. After that it republishes on every push to `main`
that touches `app/`, and can be run by hand from the Actions tab.

That page is public, like any hosted app. The publishable key is compiled into
it by design and RLS is what protects the data; signing in still requires a
Supabase user with a membership row.

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

## Running the tests locally

```
createdb kajtest
psql -d kajtest -v ON_ERROR_STOP=1 -f database/tests/supabase_stub.sql
psql -d kajtest -v ON_ERROR_STOP=1 -f database/schema.sql
for f in database/migrations/*.sql; do
  psql -d kajtest -v ON_ERROR_STOP=1 -f "$f"
done
for t in church rls invitations reports accounting audit; do
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
