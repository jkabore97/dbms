# Kaj App — Multi-Tenant Business Management Platform

One offline-first app for Kaj-consulting's clients — churches, farms, retail shops,
and whatever comes next. Each business is a tenant (`org`) with its own subdomain,
optional custom domain, roles, and modules switched on — same engine underneath.

## Structure

```
database/schema.sql             Postgres schema: tenancy, scoped roles, ledger, RLS
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
- Flutter app — not started. Next slice: church profile (Israel) end-to-end.

## Security

No live key, token, or service-account file belongs in this repo or in any chat.
Secrets go in GitHub Actions secrets and Cloudflare Worker secrets only.
