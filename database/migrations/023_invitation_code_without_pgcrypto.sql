-- ============================================================
-- 023 — MINTING AN INVITATION CODE WITHOUT PGCRYPTO
-- ============================================================
-- Generating an invitation code failed in production with:
--
--     function gen_random_bytes(integer) does not exist
--
-- which meant nobody could invite an employee at all. The button was dead in
-- front of the person trying to hire.
--
-- WHAT WENT WRONG. `gen_random_bytes()` belongs to the **pgcrypto**
-- extension. `gen_random_uuid()`, which every table in this schema defaults
-- to, is core Postgres 13+ — which is exactly why nothing else broke and this
-- looked fine everywhere anyone checked. And `create extension pgcrypto` is
-- written down in precisely one place: `database/schema.sql`, the bootstrap
-- file. It is in no migration, and therefore in none of the
-- `apply_006_to_0XX.sql` bundles, which is what actually gets pasted into the
-- Supabase SQL editor. A database brought up through the bundles never had
-- pgcrypto, and nothing in the migration history would ever have added it.
--
-- Supabase makes it worse than a missing extension: it installs extensions
-- into an `extensions` schema rather than `public`, so even "just enable
-- pgcrypto" leaves any function carrying `set search_path = public` unable to
-- see it. Fixing this by adding the extension would work on CI and stay
-- fragile on the only deployment that matters.
--
-- SO THE DEPENDENCY GOES AWAY INSTEAD. `gen_random_uuid()` is core and is
-- itself CSPRNG-backed, which is the property the original comment cared
-- about — a guessable invitation code is a guessable way into somebody's
-- books. One UUID carries 122 random bits; a code needs 40. No extension, no
-- schema ambiguity, and identical behaviour on a bare Postgres and on
-- Supabase.
--
-- The code itself is unchanged in every respect a user can see: eight
-- characters, the same 32-symbol alphabet with 0/O and 1/I stripped out
-- because these are read over a bad line, formatted XXXX-XXXX. Codes already
-- issued keep working — this replaces how the next one is minted, nothing
-- else.

create or replace function new_invitation_code()
returns text
language plpgsql
volatile
as $$
declare
    alphabet constant text := '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    v_code text;
    v_hex  text;
    v_try  int := 0;
begin
    loop
        -- 32 hex characters from core Postgres's CSPRNG.
        v_hex := replace(gen_random_uuid()::text, '-', '');

        -- Drop the version nibble (13th) and the variant nibble (17th).
        -- RFC 4122 fixes both, so they carry no entropy: leaving them in
        -- would quietly pin two of the eight characters to a short set and
        -- cost roughly ten bits of the code's strength.
        v_hex := substr(v_hex, 1, 12) || substr(v_hex, 14, 3)
                                      || substr(v_hex, 18, 15);

        v_code := '';
        for i in 1..8 loop
            -- One byte per character. 256 is an exact multiple of 32, so the
            -- modulo is uniform — with an alphabet that did not divide 256
            -- this would bias every code toward its first symbols.
            v_code := v_code || substr(
                alphabet,
                (('x' || substr(v_hex, i * 2 - 1, 2))::bit(8)::int % 32) + 1,
                1);
        end loop;

        v_code := substr(v_code, 1, 4) || '-' || substr(v_code, 5, 4);

        exit when not exists (
            select 1 from pending_invitations
            where normalize_invitation_code(code) = normalize_invitation_code(v_code)
        );

        v_try := v_try + 1;
        if v_try > 20 then
            raise exception 'could not allocate an unused invitation code';
        end if;
    end loop;
    return v_code;
end;
$$;

-- The default still points at this function; `create or replace` keeps the
-- column default pointing at the same name, so nothing else needs changing.
-- Restated anyway, so a database that somehow lost the default gets it back
-- and this migration is a complete description of the fix.
alter table pending_invitations alter column code set default new_invitation_code();

notify pgrst, 'reload schema';
