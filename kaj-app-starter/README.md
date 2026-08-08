# Kaj App — Multi-Tenant Business Management Platform

One offline-first app for Kaj-consulting's clients — churches, farms, retail shops,
and whatever comes next. Each business is a tenant (`org`) with its own subdomain,
optional custom domain, roles, and modules switched on — same engine underneath.

## Structure

```
database/schema.sql       Postgres schema: tenancy, scoped roles, ledger, RLS
.github/workflows/ci.yml  Runs on every push; validates schema, builds the app once it exists
.env.example               Required environment variables — copy to .env, never commit .env
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

## Access model — why there are no keys anywhere in this repo

- **Cloudflare**: connected via an MCP integration in the Kaj-consulting Claude
  workspace, so Claude can inspect and build there directly — no key needed.
- **GitHub**: connect this repo through claude.ai's "Add from GitHub" (read-only
  context) or through Claude Code using your own `gh auth login` (commits, PRs,
  under your approval).
- **Firebase / Play Console**: service-account credentials generated in each
  console, stored only as CI secrets — needed at deploy/publish time, not before.

Rule for all of them: no live key, token, or service-account file ever gets pasted
into a chat.
