-- ============================================================
-- test_batch190.sql — 190: Studio saves a card with its envelope.
--
-- The claims:
--   1. installed twice, the same: a card with the envelope (intro) and its
--      seal (« P&E ») passes the check, as Phanuel & Esperance's must;
--   2. a seal of more than eight characters, or with markup, refused in
--      French; an intro that is not a short word refused; a theme field
--      still unknown refused as before (182).
-- Wrapped in one transaction rolled back.
-- ============================================================
\set ON_ERROR_STOP on

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
end $$;
grant usage on schema public to anon, authenticated;
\i database/migrations/190_studio_envelope_save.sql
\i database/migrations/190_studio_envelope_save.sql

begin;
insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('19019019-0000-0000-0000-000000000001', '+22619010001', 'awa190@example.com', '{"full_name": "Awa Studio"}', now());
insert into orgs (id, name, slug, profile, default_currency, plan) values
    ('19019019-1111-0000-0000-000000000001', 'Awa Événements 190', 'awa-evenements-190', 'events', 'XOF', 'pro');
insert into events (id, org_id, created_by, kind, card, slug, preview_token, edit_token, title, starts_at, content, tz, published)
values ('19019019-2222-0000-0000-000000000001', '19019019-1111-0000-0000-000000000001', '19019019-0000-0000-0000-000000000001',
        'mariage', 'come', 'phanuel-esperance-190', left(md5('p190'), 24), left(md5('e190'), 24), 'Phanuel & Esperance',
        now() + interval '20 days', '{}'::jsonb, 'Africa/Ouagadougou', true);

do $$
declare
    e uuid := '19019019-2222-0000-0000-000000000001';
    d jsonb := '{"v": 2, "theme": {"colors": {"accent": "#7d1f2b"}, "fall": "petales", "intro": "enveloppe", "seal": "P&E"},
                 "blocks": [{"id": "pecover1", "type": "cover", "variant": "plein", "props": {"names": "Phanuel & Esperance"},
                             "style": {"bg": "film", "film": "pe-jardin", "veil": "dark", "dim": 0.32}}]}';
    c record;
    v_msg text;
begin
    perform studio_doc_check(e, d);
    perform studio_doc_check(e, jsonb_set(d, '{theme,seal}', 'null'));
    raise notice 'PASS: the envelope and its seal pass the check';

    for c in select * from (values
        ('seal too long', jsonb_set(d, '{theme,seal}', '"Phanuel&Esp"'),  'Le sceau tient en huit lettres.'),
        ('seal markup',   jsonb_set(d, '{theme,seal}', '"<b>P</b>"'),     'Le sceau tient en huit lettres.'),
        ('seal number',   jsonb_set(d, '{theme,seal}', '3'),              'Le sceau tient en huit lettres.'),
        ('intro not word', jsonb_set(d, '{theme,intro}', '"<script>"'),   'Thème mal formé (intro).'),
        ('still unknown', jsonb_set(d, '{theme,css}', '"body{}"'),        'Thème : champ inconnu (css).')
    ) as x(what, doc, expect) loop
        begin perform studio_doc_check(e, c.doc); v_msg := null;
        exception when others then v_msg := sqlerrm; end;
        assert v_msg = c.expect, c.what || ': ' || coalesce(v_msg, 'accepted') || ' (expected ' || c.expect || ')';
    end loop;
    raise notice 'PASS: a long or marked-up seal, a malformed intro, an unknown field: refused in French';
end $$;
rollback;
