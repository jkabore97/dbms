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
- R2 — pending the one-time dashboard toggle.
- `workers/tenant-router` — written, not yet deployed (`wrangler deploy`).
- Church module (`002_church_profile.sql`) — built and tested. Contributions,
  expenses, undo-by-reversal, offline idempotency, pastor's weekly summary,
  member giving statements.
- Sync support (`003_sync_support.sql`) — reversal by client_uuid, tested.
- Flutter shell (`app/`) — local SQLite with outbox, sync service, church home
  screen, contribution capture. **Not yet compiled** — needs `flutter pub get`
  and `flutter analyze` on a machine with the Flutter SDK.
- Next: login + org resolution (the orgId in main.dart is currently hardcoded),
  then the farm profile for Ignace.

## Running the app

```
cd app
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

Credentials are passed at build time, never committed. With no `--dart-define`
values the app still runs fully offline against local SQLite.

## Running the tests locally

```
createdb kajtest
psql -d kajtest -v ON_ERROR_STOP=1 -f database/tests/supabase_stub.sql
psql -d kajtest -v ON_ERROR_STOP=1 -f database/schema.sql
psql -d kajtest -v ON_ERROR_STOP=1 -f database/migrations/002_church_profile.sql
psql -d kajtest -v ON_ERROR_STOP=1 -f database/tests/test_church.sql
```

`supabase_stub.sql` fakes the `auth.users` table and `auth.uid()` that Supabase
provides, so the schema can be tested on plain Postgres. Never run it against
a real Supabase database.

## Security

No live key, token, or service-account file belongs in this repo or in any chat.
Secrets go in GitHub Actions secrets and Cloudflare Worker secrets only.
