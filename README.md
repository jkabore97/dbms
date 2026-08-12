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
- Next: the farm profile for Ignace ('farm' orgs currently land on a
  "module coming" screen), then inviting people from inside the app — today a
  membership row has to be inserted by hand.

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

## Running the tests locally

```
createdb kajtest
psql -d kajtest -v ON_ERROR_STOP=1 -f database/tests/supabase_stub.sql
psql -d kajtest -v ON_ERROR_STOP=1 -f database/schema.sql
psql -d kajtest -v ON_ERROR_STOP=1 -f database/migrations/002_church_profile.sql
psql -d kajtest -v ON_ERROR_STOP=1 -f database/migrations/003_sync_support.sql
psql -d kajtest -v ON_ERROR_STOP=1 -f database/migrations/004_rls_policies.sql
psql -d kajtest -v ON_ERROR_STOP=1 -f database/tests/test_church.sql
psql -d kajtest -v ON_ERROR_STOP=1 -f database/tests/test_rls.sql
```

Both suites seed their own rows and neither is idempotent — drop and recreate
`kajtest` between runs.

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
