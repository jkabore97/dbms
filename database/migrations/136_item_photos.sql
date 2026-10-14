-- ============================================================
-- 136_item_photos.sql — read and see an item before ordering it
-- (batch 141), for a shop, a farm and an association alike.
--
-- The owner: « when you click on an item, there is no description … Add
-- description to the process of adding an item or adding a service. Then
-- when someone clicks on the item … they can see a description and scroll
-- down, see a photo carousel. »
--
--   1. The description (064) grows from 300 to 1,000 characters: the add
--      flows now ask for it (« Décrivez-le en quelques mots ») and the
--      vitrine's item page has room for it (« Lire la suite »).
--   2. A service's duration gets its own column, products.duration_minutes
--      (1 minute to 7 days, null: not said). Until now the service flow
--      (115) wrote it into the description as « Durée : 1 h ». The backfill
--      reads what that flow wrote (« 15 min », « 30 min », « 1 h », « 2 h »,
--      « une demi-journée », « une journée », and « Autre » typed: « 45 min »,
--      « 1 h 30 », « 1h30 », « 2 heures », « 90 minutes ») off the first
--      line of a service's description, and empties the description only
--      when it is exactly that line. A duration nobody can read in minutes
--      (« 3 séances ») stays in the description, as it was.
--   3. Several photos per item. An item's photos were, and stay, documents
--      filed on it (013, 100): the vitrine's picture is its newest photo.
--      product_photos is the item's gallery, in order — each row one of
--      those photo documents — and once an item has one, its first row is
--      its cover everywhere a picture is shown (the vitrine, the search,
--      À la une, the previews, the default cover, the Articles page). An
--      item with no gallery is shown exactly as before (P1: 104 and 110).
--      Limits, held by the server for every writer:
--        * Basic: the cover only — one row — so 100's ten photographed
--          items (free_photo_items, the photo slots bought with cauris) is
--          the whole rule, unchanged;
--        * Mara Pro (and a showcase vitrine): up to max_item_photos_pro (5,
--          a platform setting, 1 to 20) photos an item;
--        * the vitrine shows no more than the business's limit today: a
--          business back on Basic shows its cover, and keeps the rest for
--          when Pro returns.
--      The doors (SECURITY INVOKER, as record_contribution: the table's
--      own policies decide — a member reads, a writer of the articles
--      writes): product_gallery, product_photo_add (files the photo onto
--      the item through 013's file_document, so 100's photo slots hold,
--      and puts it last), product_photos_order (« Mettre en premier », the
--      long-press drag), product_photo_remove (off the item; the picture
--      stays in Photos, unfiled). A photo filed onto an item that has a
--      gallery by any other path (an older app's « Changer la photo »,
--      Documents) replaces its cover, as « the newest is the one shown »
--      always meant.
--   4. The signed-out vitrine reads the photos the way it reads the cover:
--      storefront_products grows photo_keys (text[], in order, cover first;
--      null without a photo) and duration_minutes. Its grants are said
--      again (anon and authenticated). The uploads Worker serves each
--      photo through storefront_photo_allowed (100/127), unchanged: every
--      gallery photo is a photo document on its item.
--
-- product_photos: RLS like products (read by a member, written by
-- whoever may edit the articles), nothing for anon, 127's same_org guard
-- (product_id → products, document_id → documents).
-- ============================================================

-- ------------------------------------------------------------
-- 1. The description: up to 1,000 characters
-- ------------------------------------------------------------
alter table products drop constraint if exists products_description_length;
alter table products add constraint products_description_length
    check (description is null or char_length(description) <= 1000);

-- ------------------------------------------------------------
-- 2. A service's duration
-- ------------------------------------------------------------
alter table products add column if not exists duration_minutes integer;
alter table products drop constraint if exists products_duration_minutes_range;
alter table products add constraint products_duration_minutes_range
    check (duration_minutes is null or duration_minutes between 1 and 10080);
comment on column products.duration_minutes is
    'How long a service takes, in minutes (136); null when not said. Shown « Durée : 1 h » on the vitrine.';

-- What the service flow wrote after « Durée : », in minutes; null when it
-- is not a length of time.
create or replace function duration_minutes_of(p_text text)
returns integer
language plpgsql
immutable
set search_path = public
as $$
declare
    t text := lower(btrim(coalesce(p_text, '')));
    m text[];
    v numeric;
begin
    t := regexp_replace(t, '^dur[ée]e\s*:\s*', '');
    t := regexp_replace(t, '\s+', ' ', 'g');
    t := regexp_replace(t, '^(environ|env\.|~)\s*', '');
    if t in ('une demi-journée', 'demi-journée', 'une demi journée', 'demi journée', '1/2 journée') then
        return 240;
    end if;
    if t in ('une journée', 'journée', '1 journée', 'un jour', '1 jour') then
        return 480;
    end if;
    m := regexp_match(t, '^(\d+(?:[.,]\d+)?) ?(?:h|hr|hrs|heure|heures)(?: ?(\d{1,2}))? ?(?:min|mn|minutes?)?$');
    if m is not null then
        v := replace(m[1], ',', '.')::numeric * 60 + coalesce(m[2], '0')::numeric;
    else
        m := regexp_match(t, '^(\d+) ?(?:min|mn|minute|minutes)$');
        if m is null then
            return null;
        end if;
        v := m[1]::numeric;
    end if;
    v := round(v);
    if v < 1 or v > 10080 then
        return null;
    end if;
    return v::int;
end;
$$;

-- The backfill: a service whose description opens with « Durée : … » read
-- in minutes. The description goes only when it is exactly that line.
with d as (
    select p.id,
           duration_minutes_of(m[1]) as minutes,
           btrim(p.description) ~ '^Dur[ée]e\s*:\s*[^\n]+$' as exact
      from products p
     cross join lateral regexp_match(btrim(p.description), '^Dur[ée]e\s*:\s*([^\n]+)') m
     where p.is_service
       and p.duration_minutes is null
       and p.description is not null
)
update products p
   set duration_minutes = d.minutes,
       description      = case when d.exact then null else p.description end
  from d
 where d.id = p.id
   and d.minutes is not null;

-- ------------------------------------------------------------
-- 3. The setting: photos an item on Mara Pro
-- ------------------------------------------------------------
insert into platform_settings (key, value) values ('max_item_photos_pro', '5')
on conflict (key) do nothing;

create or replace function trg_settings_136()
returns trigger
language plpgsql
set search_path = public
as $$
declare v numeric;
begin
    if jsonb_typeof(new.value) <> 'number' then
        raise exception 'Ce réglage attend un nombre.';
    end if;
    v := (new.value #>> '{}')::numeric;
    if v < 1 or v > 20 or v <> trunc(v) then
        raise exception 'De 1 à 20 photos par article, s''il vous plaît.';
    end if;
    return new;
end;
$$;

drop trigger if exists settings_136_check on platform_settings;
create trigger settings_136_check
before insert or update on platform_settings
for each row when (new.key = 'max_item_photos_pro')
execute function trg_settings_136();

-- How many photos an item of this business may show and hold: the cover
-- alone on Basic, max_item_photos_pro on Mara Pro or a showcase vitrine.
-- Null for no such business.
create or replace function item_photo_limit(p_org_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
    select case
        when org_plan(o.id) = 'pro' or o.showcase then
            least(greatest(coalesce(
                (select (s.value #>> '{}')::int from platform_settings s
                  where s.key = 'max_item_photos_pro' and jsonb_typeof(s.value) = 'number'), 5), 1), 20)
        else 1
    end
    from orgs o where o.id = p_org_id;
$$;

-- ------------------------------------------------------------
-- 4. The gallery
-- ------------------------------------------------------------
create table if not exists product_photos (
    id          uuid primary key default gen_random_uuid(),
    org_id      uuid not null references orgs(id) on delete cascade,
    product_id  uuid not null references products(id) on delete cascade,
    document_id uuid not null references documents(id) on delete cascade,
    photo_key   text not null,
    position    integer not null check (position between 0 and 99),
    created_at  timestamptz not null default now(),
    constraint product_photos_position_key unique (product_id, position)
        deferrable initially deferred,
    constraint product_photos_document_key unique (product_id, document_id)
);
create index if not exists product_photos_document_idx on product_photos (document_id);
create index if not exists product_photos_org_idx on product_photos (org_id);

comment on table product_photos is
    'An item''s photos in order (136): each a photo document filed on it; the first is its cover.';

-- Each row one of the item's own photographs (never paperwork, never
-- another item's), its key the document's, its business the item's.
create or replace function trg_product_photos_check()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_doc documents%rowtype;
begin
    select * into v_doc from documents where id = new.document_id;
    if not found or v_doc.product_id is distinct from new.product_id
       or not doc_is_photo(v_doc.kind, v_doc.content_type) then
        raise exception 'Cette photo n''est pas une photo de cet article.'
            using errcode = 'check_violation';
    end if;
    new.photo_key := v_doc.r2_key;
    if new.org_id is null then
        new.org_id := (select org_id from products where id = new.product_id);
    end if;
    return new;
end;
$$;

drop trigger if exists product_photos_check on product_photos;
create trigger product_photos_check
before insert or update on product_photos
for each row execute function trg_product_photos_check();

-- The limit, for every writer: one at a time per item.
create or replace function trg_product_photos_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_limit int;
begin
    -- A row moved onto another item counts there as a new one.
    if tg_op = 'UPDATE' and new.product_id = old.product_id then
        return new;
    end if;
    perform pg_advisory_xact_lock(hashtext('item_photos:' || new.product_id::text));
    v_limit := coalesce(item_photo_limit(new.org_id), 1);
    if (select count(*) from product_photos where product_id = new.product_id) >= v_limit then
        if v_limit <= 1 then
            raise exception 'Mara Pro : plusieurs photos par article. Sans Pro, un article garde une photo.'
                using errcode = 'check_violation';
        end if;
        raise exception 'Pas plus de % photos par article.', v_limit
            using errcode = 'check_violation';
    end if;
    return new;
end;
$$;

drop trigger if exists product_photos_limit on product_photos;
create trigger product_photos_limit
before insert or update of product_id on product_photos
for each row execute function trg_product_photos_limit();

-- 127's guard: the row, its item and its photo are one business's.
drop trigger if exists same_org on product_photos;
create trigger same_org before insert or update on product_photos
for each row execute function trg_same_org('product_id:products', 'document_id:documents');

alter table product_photos enable row level security;
revoke all on product_photos from public;

drop policy if exists "product photos readable within org" on product_photos;
create policy "product photos readable within org"
on product_photos for select using (is_org_member(org_id));

drop policy if exists "product photos added by staff" on product_photos;
create policy "product photos added by staff"
on product_photos for insert
with check (can_write_org(org_id) and feature_access(org_id, 'products') = 'edit');

drop policy if exists "product photos ordered by staff" on product_photos;
create policy "product photos ordered by staff"
on product_photos for update
using (can_write_org(org_id) and feature_access(org_id, 'products') = 'edit')
with check (can_write_org(org_id) and feature_access(org_id, 'products') = 'edit');

drop policy if exists "product photos removed by staff" on product_photos;
create policy "product photos removed by staff"
on product_photos for delete
using (can_write_org(org_id) and feature_access(org_id, 'products') = 'edit');

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke all on product_photos from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant select, insert, update, delete on product_photos to authenticated;
    end if;
end $$;

-- The documents follow: a photo moved off its item or re-filed as
-- paperwork leaves the gallery; a new key follows its row; a photo filed
-- onto an item that has a gallery by any path but product_photo_add (an
-- older app's « Changer la photo », Documents) becomes its cover, in the
-- old cover's place — « the newest is the one shown », as before.
create or replace function trg_documents_gallery()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_first uuid;
begin
    if tg_op = 'UPDATE' then
        if old.product_id is not null
           and (new.product_id is distinct from old.product_id
                or not doc_is_photo(new.kind, new.content_type)) then
            delete from product_photos where document_id = new.id and product_id = old.product_id;
        elsif new.r2_key is distinct from old.r2_key then
            update product_photos set photo_key = new.r2_key where document_id = new.id;
        end if;
    end if;
    if new.product_id is not null
       and doc_is_photo(new.kind, new.content_type)
       and (tg_op = 'INSERT'
            or old.product_id is distinct from new.product_id
            or not doc_is_photo(old.kind, old.content_type))
       and coalesce(current_setting('mara.gallery_doc', true), '') <> new.id::text
       and not exists (select 1 from product_photos where document_id = new.id) then
        select id into v_first from product_photos
         where product_id = new.product_id order by position limit 1;
        if v_first is not null then
            update product_photos set document_id = new.id, photo_key = new.r2_key
             where id = v_first;
        end if;
    end if;
    return null;
end;
$$;

drop trigger if exists documents_gallery on documents;
create trigger documents_gallery
after insert or update of product_id, kind, content_type, r2_key on documents
for each row execute function trg_documents_gallery();

-- An item's photos as the street is shown them: the gallery, as many as
-- the business may show today, or its newest photo; null without one.
create or replace function item_gallery_keys(p_product_id uuid, p_org_id uuid)
returns text[]
language sql
stable
security definer
set search_path = public
as $$
    select coalesce(
        (select array_agg(g.k order by g.pos)
           from (select d.r2_key as k, pp.position as pos
                   from product_photos pp
                   join documents d on d.id = pp.document_id and d.product_id = pp.product_id
                  where pp.product_id = p_product_id
                    and doc_is_photo(d.kind, d.content_type)
                  order by pp.position
                  limit coalesce(item_photo_limit(p_org_id), 1)) g),
        (select array[d.r2_key] from documents d
          where d.product_id = p_product_id and doc_is_photo(d.kind, d.content_type)
          order by coalesce(d.captured_at, d.created_at) desc
          limit 1));
$$;

-- An item's cover: its gallery's first photo, or its newest photo (100).
create or replace function product_cover_key(p_product_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
    select coalesce(
        (select d.r2_key from product_photos pp
           join documents d on d.id = pp.document_id and d.product_id = pp.product_id
          where pp.product_id = p_product_id and doc_is_photo(d.kind, d.content_type)
          order by pp.position limit 1),
        (select d.r2_key from documents d
          where d.product_id = p_product_id and doc_is_photo(d.kind, d.content_type)
          order by coalesce(d.captured_at, d.created_at) desc
          limit 1));
$$;

-- ------------------------------------------------------------
-- 5. The owner's doors (SECURITY INVOKER: the policies decide)
-- ------------------------------------------------------------
-- The item's photos in order and how many it may hold. Without a gallery
-- the photo shown today stands alone, first.
create or replace function product_gallery(p_product_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
    select jsonb_build_object(
        'product_id', p.id,
        'limit',      item_photo_limit(p.org_id),
        'photos',     coalesce(
            (select jsonb_agg(jsonb_build_object('document_id', d.id, 'photo_key', d.r2_key)
                              order by pp.position)
               from product_photos pp
               join documents d on d.id = pp.document_id and d.product_id = pp.product_id
              where pp.product_id = p.id and doc_is_photo(d.kind, d.content_type)),
            (select jsonb_build_array(jsonb_build_object('document_id', c.id, 'photo_key', c.r2_key))
               from (select d.id, d.r2_key from documents d
                      where d.product_id = p.id and doc_is_photo(d.kind, d.content_type)
                      order by coalesce(d.captured_at, d.created_at) desc
                      limit 1) c),
            '[]'::jsonb))
    from products p
    where p.id = p_product_id;
$$;

-- One more photo, last. The picture is a document of the business already
-- (the app sends the bytes first, 013); it is filed onto the item through
-- file_document — 100's photo slots hold there — then put in the gallery.
-- An item with no gallery yet keeps its photo first.
create or replace function product_photo_add(p_product_id uuid, p_document_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = public, auth
as $$
declare
    v_org    uuid;
    v_doc    documents%rowtype;
    v_cover  documents%rowtype;
    v_count  int;
    v_limit  int;
begin
    if auth.uid() is null then
        raise exception 'product_photo_add() needs a signed-in caller';
    end if;
    select org_id into v_org from products where id = p_product_id;
    if v_org is null then
        raise exception 'Article introuvable.';
    end if;
    if not can_write_org(v_org) or feature_access(v_org, 'products') <> 'edit' then
        raise exception 'Vous ne pouvez pas changer les photos de cet article.';
    end if;
    select * into v_doc from documents where id = p_document_id and org_id = v_org;
    if not found or not doc_is_photo(v_doc.kind, v_doc.content_type) then
        raise exception 'Photo introuvable.';
    end if;
    if v_doc.product_id is not null and v_doc.product_id <> p_product_id then
        raise exception 'Cette photo est déjà sur un autre article.';
    end if;
    if exists (select 1 from product_photos where product_id = p_product_id and document_id = p_document_id) then
        return product_gallery(p_product_id);
    end if;

    perform pg_advisory_xact_lock(hashtext('item_photos:' || p_product_id::text));
    select count(*) into v_count from product_photos where product_id = p_product_id;
    if v_count = 0 then
        select d.* into v_cover from documents d
         where d.product_id = p_product_id and d.id <> p_document_id
           and doc_is_photo(d.kind, d.content_type)
         order by coalesce(d.captured_at, d.created_at) desc
         limit 1;
        if v_cover.id is not null then
            v_count := 1;
        end if;
    end if;
    v_limit := coalesce(item_photo_limit(v_org), 1);
    if v_count >= v_limit then
        if v_limit <= 1 then
            raise exception 'Mara Pro : plusieurs photos par article. Sans Pro, un article garde une photo.'
                using errcode = 'check_violation';
        end if;
        raise exception 'Pas plus de % photos par article.', v_limit
            using errcode = 'check_violation';
    end if;
    if v_cover.id is not null then
        insert into product_photos (org_id, product_id, document_id, photo_key, position)
        values (v_org, p_product_id, v_cover.id, v_cover.r2_key, 0);
    end if;

    perform set_config('mara.gallery_doc', p_document_id::text, true);
    if v_doc.product_id is null then
        perform file_document(p_document_id, null, null, null, p_product_id);
    end if;
    perform set_config('mara.gallery_doc', '', true);

    insert into product_photos (org_id, product_id, document_id, photo_key, position)
    values (v_org, p_product_id, p_document_id, v_doc.r2_key,
            coalesce((select max(position) + 1 from product_photos where product_id = p_product_id), 0));
    return product_gallery(p_product_id);
end;
$$;

-- The photos in a new order (« Mettre en premier », the drag): every one
-- of the item's photos, each once. The first is the cover.
create or replace function product_photos_order(p_product_id uuid, p_document_ids uuid[])
returns jsonb
language plpgsql
security invoker
set search_path = public, auth
as $$
declare
    v_org uuid;
    v_ids uuid[];
begin
    if auth.uid() is null then
        raise exception 'product_photos_order() needs a signed-in caller';
    end if;
    select org_id into v_org from products where id = p_product_id;
    if v_org is null then
        raise exception 'Article introuvable.';
    end if;
    if not can_write_org(v_org) or feature_access(v_org, 'products') <> 'edit' then
        raise exception 'Vous ne pouvez pas changer les photos de cet article.';
    end if;
    select array_agg(document_id order by document_id) into v_ids
      from product_photos where product_id = p_product_id;
    if v_ids is null then
        -- No gallery: one photo, already first.
        if coalesce(array_length(p_document_ids, 1), 0) <= 1 then
            return product_gallery(p_product_id);
        end if;
        raise exception 'L''ordre ne correspond pas aux photos de l''article.';
    end if;
    if (select array_agg(x order by x) from (select distinct unnest(p_document_ids) x) u) is distinct from v_ids
       or array_length(p_document_ids, 1) <> array_length(v_ids, 1) then
        raise exception 'L''ordre ne correspond pas aux photos de l''article.';
    end if;
    update product_photos pp
       set position = o.n - 1
      from unnest(p_document_ids) with ordinality o(doc, n)
     where pp.product_id = p_product_id and pp.document_id = o.doc
       and pp.position <> o.n - 1;
    return product_gallery(p_product_id);
end;
$$;

-- One photo off the item. It stays in Photos, unfiled (nothing is lost);
-- the next one becomes the cover. The last one gone, the item has no photo:
-- the older pictures it hid are unfiled too, so none comes back by itself.
create or replace function product_photo_remove(p_product_id uuid, p_document_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = public, auth
as $$
declare
    v_org   uuid;
    v_gone  int;
    v_cover boolean;
begin
    if auth.uid() is null then
        raise exception 'product_photo_remove() needs a signed-in caller';
    end if;
    select org_id into v_org from products where id = p_product_id;
    if v_org is null then
        raise exception 'Article introuvable.';
    end if;
    if not can_write_org(v_org) or feature_access(v_org, 'products') <> 'edit' then
        raise exception 'Vous ne pouvez pas changer les photos de cet article.';
    end if;
    -- One of the item's photos, never its paperwork (an invoice filed on it).
    if not exists (select 1 from documents
                    where id = p_document_id and product_id = p_product_id
                      and doc_is_photo(kind, content_type)) then
        raise exception 'Photo introuvable.';
    end if;
    -- Without a gallery, the photo shown is the newest: removing it is
    -- removing the last one.
    v_cover := not exists (select 1 from product_photos where product_id = p_product_id)
        and p_document_id = (select d.id from documents d
                              where d.product_id = p_product_id
                                and doc_is_photo(d.kind, d.content_type)
                              order by coalesce(d.captured_at, d.created_at) desc
                              limit 1);
    delete from product_photos where product_id = p_product_id and document_id = p_document_id;
    get diagnostics v_gone = row_count;
    update documents set product_id = null
     where id = p_document_id and product_id = p_product_id;
    -- Positions from 0 again, in the same order.
    update product_photos pp
       set position = r.n - 1
      from (select id, row_number() over (order by position) as n
              from product_photos where product_id = p_product_id) r
     where pp.id = r.id and pp.position <> r.n - 1;
    if (v_gone > 0 or v_cover)
       and not exists (select 1 from product_photos where product_id = p_product_id) then
        update documents set product_id = null
         where product_id = p_product_id and doc_is_photo(kind, content_type);
    end if;
    return product_gallery(p_product_id);
end;
$$;

-- ------------------------------------------------------------
-- 6. Every picture the cover: the gallery's first
-- ------------------------------------------------------------
-- storefront_products: 131's, with the photos in order and the duration.
-- Its return table grows, so it is dropped and recreated, its grants said
-- again (063: a new function is born closed).
drop function if exists storefront_products(text);
create function storefront_products(p_slug text)
returns table (
    id               uuid,
    name             text,
    sale_price       numeric,
    in_stock         boolean,
    photo_key        text,
    description      text,
    unit             text,
    available_from   date,
    is_service       boolean,
    price_from       boolean,
    photo_keys       text[],
    duration_minutes integer
)
language sql
stable
security definer
set search_path = public
as $$
    select p.id, p.name, p.sale_price,
           (p.is_service
            or p.quantity > 0
            or not p.stock_tracked
            or p.available_from > (now() at time zone 'Africa/Ouagadougou')::date),
           g.keys[1],
           nullif(btrim(p.description), ''),
           nullif(btrim(p.unit), ''),
           case when p.available_from > (now() at time zone 'Africa/Ouagadougou')::date
                then p.available_from end,
           p.is_service,
           p.price_from,
           g.keys,
           p.duration_minutes
    from products p
    cross join lateral (select item_gallery_keys(p.id, p.org_id) as keys) g
    where p.org_id = storefront_open(p_slug)
      and p.is_active
      and p.is_published
      and vitrine_shows(p.org_id, p.is_service)
    order by p.is_service, p.name;
$$;

-- storefront_featured: 131's, its picture the cover.
create or replace function storefront_featured()
returns table (
    id         uuid,
    name       text,
    sale_price numeric,
    in_stock   boolean,
    photo_key  text,
    shop_name  text,
    shop_slug  text,
    currency   text
)
language sql
stable
security definer
set search_path = public
as $$
    select p.id, p.name, p.sale_price, (p.is_service or p.quantity > 0 or not p.stock_tracked),
           product_cover_key(p.id),
           o.name, o.slug, o.default_currency
    from products p
    join orgs o on o.id = p.org_id
    left join lateral (
        select min(pm.starts_at) as since from promotions pm
         where pm.product_id = p.id and pm.status = 'approved'
           and pm.starts_at <= now() and pm.ends_at > now()
    ) spot on true
    where (spot.since is not null or p.featured_until > now())
      and p.is_active
      and p.is_published
      and vitrine_shows(p.org_id, p.is_service)
      -- « Mettre en avant » hidden: Mara's own picks go too (a spot paid
      -- for keeps the switch from hiding anything, feature_paid).
      and not feature_hidden(o.id, 'spots')
      and o.storefront_enabled
      and o.archived_at  is null
      and o.suspended_at is null
    order by (spot.since is null), spot.since, p.featured_until desc nulls last, p.name
    limit 12;
$$;

-- search_products: 131's, its picture the cover.
create or replace function search_products(
    p_query text,
    p_lat   double precision default null,
    p_lng   double precision default null
)
returns table (
    id          uuid,
    name        text,
    sale_price  numeric,
    in_stock    boolean,
    photo_key   text,
    shop_name   text,
    shop_slug   text,
    currency    text,
    shop_lat    double precision,
    shop_lng    double precision,
    distance_km double precision
)
language sql
stable
security definer
set search_path = public
as $$
    with q as (
        select fold_search_text(btrim(coalesce(p_query, ''))) as folded
    ),
    hits as (
        select p.id, p.name, p.sale_price,
               (p.is_service or p.quantity > 0 or not p.stock_tracked) as in_stock,
               product_cover_key(p.id) as photo_key,
               o.name as shop_name, o.slug as shop_slug,
               o.default_currency as currency,
               o.lat as shop_lat, o.lng as shop_lng,
               case
                   when p_lat is null or p_lng is null
                     or o.lat is null or o.lng is null then null
                   else 6371.0 * 2 * asin(sqrt(
                            power(sin(radians(o.lat - p_lat) / 2), 2)
                          + cos(radians(p_lat)) * cos(radians(o.lat))
                          * power(sin(radians(o.lng - p_lng) / 2), 2)))
               end as distance_km,
               position((select folded from q) in fold_search_text(p.name))
                   as hit_at
        from products p
        join orgs o on o.id = p.org_id
        where length((select folded from q)) >= 2
          and fold_search_text(p.name) like
              '%' || replace(replace(replace((select folded from q),
                    '\', '\\'), '%', '\%'), '_', '\_') || '%'
          and p.is_active
          and p.is_published
          and vitrine_shows(p.org_id, p.is_service)
          and o.storefront_enabled
          and o.archived_at  is null
          and o.suspended_at is null
    )
    select h.id, h.name, h.sale_price, h.in_stock, h.photo_key,
           h.shop_name, h.shop_slug, h.currency,
           h.shop_lat, h.shop_lng, h.distance_km
    from hits h
    order by (h.hit_at = 1) desc, h.in_stock desc,
             (h.distance_km is null), h.distance_km, h.name, h.shop_name
    limit 50;
$$;

-- storefront_previews: 131's, its picture the cover.
create or replace function storefront_previews(p_slugs text[])
returns table (
    slug       text,
    product_id uuid,
    name       text,
    sale_price numeric,
    photo_key  text
)
language sql
stable
security definer
set search_path = public
as $$
    select x.slug, x.id, x.name, x.sale_price, x.photo_key
    from (
        select o.slug, p.id, p.name, p.sale_price, ph.r2_key as photo_key,
               row_number() over (
                   partition by o.id
                   order by (ph.r2_key is null),
                            (not p.is_service and p.stock_tracked and p.quantity <= 0), p.name
               ) as n
        from orgs o
        join products p on p.org_id = o.id
        left join lateral (select product_cover_key(p.id) as r2_key) ph on true
        where o.slug = any (coalesce(p_slugs, '{}'))
          and o.id = storefront_open(o.slug)
          and p.is_active
          and p.is_published
          and vitrine_shows(p.org_id, p.is_service)
    ) x
    where x.n <= 3
    order by x.slug, x.n;
$$;

-- vitrine_default_style: 110's, « the first photo » the first item's cover.
create or replace function vitrine_default_style(p_org uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select coalesce((
        select jsonb_strip_nulls(jsonb_build_object(
                   'accent', d.v ->> 'accent',
                   'layout', nullif(d.v ->> 'layout', 'grid'),
                   'cover_key', case when d.v ->> 'cover' = 'first_photo' then (
                       select product_cover_key(p.id)
                         from products p
                        where p.org_id = o.id and p.is_active and p.is_published
                          and exists (select 1 from documents doc
                                       where doc.product_id = p.id
                                         and doc_is_photo(doc.kind, doc.content_type))
                        order by p.is_service, p.name
                        limit 1) end))
               - case when vitrine_plus_on(o.id) then '{}'::text[]
                      else array['layout'] end
          from orgs o
          cross join lateral (select kind_setting(o.profile::text, 'vitrine_default') as v) d
         where o.id = p_org
           and o.storefront_style = '{}'::jsonb
           and not o.showcase
           and jsonb_typeof(d.v) = 'object'
           and (vitrine_plus_on(o.id) or cauris_param('vitrine_free_basics', 1) = 1)),
        '{}'::jsonb);
$$;

-- product_photo_keys: 100's thumbnails on the Articles page, the cover
-- first. Invoker as before: documents' own policies decide what is seen.
create or replace function product_photo_keys(p_org_id uuid)
returns table (product_id uuid, photo_key text)
language sql
stable
security invoker
set search_path = public
as $$
    select distinct on (x.product_id) x.product_id, x.r2_key
    from (
        select d.product_id, d.r2_key, 0 as rank, pp.position as pos,
               coalesce(d.captured_at, d.created_at) as at
          from product_photos pp
          join documents d on d.id = pp.document_id and d.product_id = pp.product_id
         where pp.org_id = p_org_id and doc_is_photo(d.kind, d.content_type)
        union all
        select d.product_id, d.r2_key, 1, 0, coalesce(d.captured_at, d.created_at)
          from documents d
         where d.org_id = p_org_id
           and d.product_id is not null
           and doc_is_photo(d.kind, d.content_type)
    ) x
    order by x.product_id, x.rank, x.pos, x.at desc;
$$;

-- ------------------------------------------------------------
-- 7. Grants
-- ------------------------------------------------------------
revoke execute on function duration_minutes_of(text)                  from public;
revoke execute on function trg_settings_136()                         from public;
revoke execute on function item_photo_limit(uuid)                     from public;
revoke execute on function trg_product_photos_check()                 from public;
revoke execute on function trg_product_photos_limit()                 from public;
revoke execute on function trg_documents_gallery()                    from public;
revoke execute on function item_gallery_keys(uuid, uuid)              from public;
revoke execute on function product_cover_key(uuid)                    from public;
revoke execute on function product_gallery(uuid)                      from public;
revoke execute on function product_photo_add(uuid, uuid)              from public;
revoke execute on function product_photos_order(uuid, uuid[])         from public;
revoke execute on function product_photo_remove(uuid, uuid)           from public;
revoke execute on function storefront_products(text)                  from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function duration_minutes_of(text)          from anon;
        revoke execute on function trg_settings_136()                 from anon;
        revoke execute on function item_photo_limit(uuid)             from anon;
        revoke execute on function trg_product_photos_check()         from anon;
        revoke execute on function trg_product_photos_limit()         from anon;
        revoke execute on function trg_documents_gallery()            from anon;
        revoke execute on function item_gallery_keys(uuid, uuid)      from anon;
        revoke execute on function product_cover_key(uuid)            from anon;
        revoke execute on function product_gallery(uuid)              from anon;
        revoke execute on function product_photo_add(uuid, uuid)      from anon;
        revoke execute on function product_photos_order(uuid, uuid[]) from anon;
        revoke execute on function product_photo_remove(uuid, uuid)   from anon;
        -- The signed-out vitrine reads the shelf, its photos included.
        grant execute on function storefront_products(text)           to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke execute on function duration_minutes_of(text)          from authenticated;
        revoke execute on function trg_settings_136()                 from authenticated;
        revoke execute on function trg_product_photos_check()         from authenticated;
        revoke execute on function trg_product_photos_limit()         from authenticated;
        revoke execute on function trg_documents_gallery()            from authenticated;
        revoke execute on function item_gallery_keys(uuid, uuid)      from authenticated;
        revoke execute on function product_cover_key(uuid)            from authenticated;
        -- product_gallery and product_photo_add (invokers) ask it.
        grant execute on function item_photo_limit(uuid)              to authenticated;
        grant execute on function product_gallery(uuid)               to authenticated;
        grant execute on function product_photo_add(uuid, uuid)       to authenticated;
        grant execute on function product_photos_order(uuid, uuid[])  to authenticated;
        grant execute on function product_photo_remove(uuid, uuid)    to authenticated;
        grant execute on function storefront_products(text)           to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
