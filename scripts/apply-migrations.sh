#!/usr/bin/env bash
#
# Applies the migrations a database has not had yet, each in its own
# transaction, and records each in kaj_migrations as it lands.
#
# Why: migrations reached the live database by pasting a bundle into the
# SQL editor, or by hand through a tool that held any statement containing
# DROP for an approval nobody saw (the October audit). A skipped or
# half-applied migration is the risk; this makes "applied" a row in a table
# and every apply all-or-nothing.
#
# Usage:  DATABASE_URL=postgres://… scripts/apply-migrations.sh
#         DATABASE_URL=… BASELINE=073 scripts/apply-migrations.sh
#
# On a database with no ledger yet, BASELINE says which migrations are
# already there: everything up to and including it is recorded without being
# run. Without BASELINE an empty ledger is refused — a live database is never
# assumed to be empty.
#
# The ledger table is created here, not in a migration: it describes the
# migrations and cannot be one of them.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

: "${DATABASE_URL:?DATABASE_URL is required}"
psql_q=(psql "$DATABASE_URL" -X -q -v ON_ERROR_STOP=1 -t -A)

"${psql_q[@]}" -c "
create table if not exists kaj_migrations (
    name       text primary key,
    applied_at timestamptz not null default now()
);
alter table kaj_migrations enable row level security;
revoke all on kaj_migrations from public;
" >/dev/null

count="$("${psql_q[@]}" -c 'select count(*) from kaj_migrations')"
if [ "$count" = "0" ]; then
    if [ -z "${BASELINE:-}" ]; then
        echo "kaj_migrations is empty. Say which migrations are already applied:" >&2
        echo "  BASELINE=<last applied number, e.g. 073> $0" >&2
        exit 2
    fi
    for f in database/migrations/*.sql; do
        name="$(basename "$f")"
        n="${name%%_*}"
        if [[ "$n" < "$BASELINE" || "$n" == "$BASELINE" ]]; then
            "${psql_q[@]}" -c "insert into kaj_migrations (name) values ('$name') on conflict do nothing" >/dev/null
        fi
    done
    echo "Baseline recorded up to $BASELINE."
fi

applied=0
for f in database/migrations/*.sql; do
    name="$(basename "$f")"
    done_already="$("${psql_q[@]}" -c "select 1 from kaj_migrations where name = '$name'")"
    if [ -n "$done_already" ]; then
        continue
    fi
    echo "Applying $name"
    # One transaction: the migration and its ledger row land together, or
    # neither does.
    {
        echo 'begin;'
        cat "$f"
        echo
        echo "insert into kaj_migrations (name) values ('$name');"
        echo 'commit;'
    } | psql "$DATABASE_URL" -X -q -v ON_ERROR_STOP=1 >/dev/null
    applied=$((applied + 1))
done

echo "Migrations applied: $applied."
