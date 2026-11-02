-- ============================================================
-- test_batch166.sql — 166: concerts, festivals, conferences.
--   1. the three new kinds are taken; an unknown one is still refused;
--   2. « Dix ans » is drawn for them. Installed twice; rolled back.
-- ============================================================
\set ON_ERROR_STOP on
\i database/migrations/166_events_kinds.sql
\i database/migrations/166_events_kinds.sql

begin;
insert into orgs (id, name, slug, profile, default_currency, plan) values
    ('16616616-1111-0000-0000-000000000001', 'Scène 166', 'scene-166', 'events', 'XOF', 'free');
do $$
declare k text; v_err text;
begin
    foreach k in array array['concert', 'culture', 'conference'] loop
        insert into events (org_id, kind, card, slug, preview_token, edit_token, title, content, tz)
        values ('16616616-1111-0000-0000-000000000001', k, 'gala', k || '-166', rpad(k, 24, 'x'), rpad(k, 24, 'y'), 'Soirée ' || k, '{}', 'Africa/Ouagadougou');
    end loop;
    begin
        insert into events (org_id, kind, card, slug, preview_token, edit_token, title, content, tz)
        values ('16616616-1111-0000-0000-000000000001', 'rodeo', 'gala', 'rodeo-166', rpad('r', 24, 'x'), rpad('r', 24, 'y'), 'Rodéo', '{}', 'Africa/Ouagadougou');
        raise exception 'an unknown kind was taken';
    exception when check_violation then null;
    end;
    assert (select kinds @> array['gala', 'concert', 'culture', 'conference'] from event_templates where key = 'gala'), 'Dix ans for the stage too';
    raise notice 'PASS: 166 — concerts, festivals and conferences are kinds of event; « Dix ans » is drawn for them';
end $$;
rollback;
