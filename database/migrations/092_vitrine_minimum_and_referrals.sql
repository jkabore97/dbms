-- ============================================================
-- 092_vitrine_minimum_and_referrals.sql — a vitrine opens with 8 items;
-- sponsoring pays on its own and says how much.
--
-- 1. The owner: « Do not permit vitrine to a business if they do not have
--    more than 7 items for sale. » A vitrine is public — its page, the
--    street, the directory — only with 8 items on sale (active and
--    published). Below that the owner may switch it on and prepare it, and
--    still sees it themselves; the public does not. The vitrine's score
--    counts « 8 articles sur la vitrine » as its first step, so the tools
--    it opens (089) are not reached by a one-item window. The minimum is a
--    platform setting (vitrine_min_items).
--
-- 2. Sponsoring. The 200 cauris for a referred business that takes off
--    (vitrine complete, 3 finished orders) were checked only when that
--    business opened « Mes cauris », so a sponsor could wait forever. The
--    check now runs as each order is finished. my_cauris() also says what a
--    referral pays and lists the businesses sponsored, each with how far it
--    is from paying.
--
-- No destructive statement: functions replaced in place with their own
-- signatures, a trigger created where missing.
-- ============================================================

insert into platform_settings (key, value) values ('vitrine_min_items', '8')
on conflict (key) do nothing;

create or replace function vitrine_items(p_org_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
    select count(*)::int from products p
     where p.org_id = p_org_id and p.is_active and p.is_published;
$$;

-- 052's door, with the minimum. The business's own people still open it,
-- to see what they are preparing.
create or replace function storefront_open(p_slug text)
returns uuid
language sql
stable
security definer
set search_path = public, auth
as $$
    select o.id
    from orgs o
    where o.slug = lower(btrim(coalesce(p_slug, '')))
      and o.storefront_enabled
      and o.archived_at  is null
      and o.suspended_at is null
      and (vitrine_items(o.id) >= cauris_param('vitrine_min_items', 8)
           or exists (select 1 from memberships m
                       where m.org_id = o.id and m.user_id = auth.uid()));
$$;

-- 084's score: the first step is now the minimum, not a single item.
create or replace function vitrine_score(p_org_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
    select (100 * (
        (published >= greatest(cauris_param('vitrine_min_items', 8), 1))::int
      + (with_photo >= 3 or (published > 0 and with_photo >= published))::int
      + blurb::int + phone::int + address::int + pin::int) / 6.0)::int
    from (
        select
            (select count(*) from products p
              where p.org_id = o.id and p.is_active and p.is_published) as published,
            (select count(*) from products p
              where p.org_id = o.id and p.is_active and p.is_published
                and exists (select 1 from documents d where d.product_id = p.id)) as with_photo,
            nullif(btrim(coalesce(o.storefront_blurb, '')), '') is not null as blurb,
            nullif(btrim(coalesce(o.phone, '')), '') is not null as phone,
            nullif(btrim(coalesce(o.address, '')), '') is not null as address,
            (o.lat is not null and o.lng is not null) as pin
        from orgs o where o.id = p_org_id
    ) x;
$$;

-- 070's checklist, saying the minimum.
create or replace function vitrine_checklist(p_org_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, auth
as $$
    select case when not is_org_member(p_org_id) then null else
    jsonb_build_object(
        'open',        o.storefront_enabled,
        'min_items',   cauris_param('vitrine_min_items', 8),
        'active',      (select count(*) from products p
                         where p.org_id = o.id and p.is_active and not p.is_ingredient),
        'published',   (select count(*) from products p
                         where p.org_id = o.id and p.is_active and p.is_published),
        'unpublished', (select count(*) from products p
                         where p.org_id = o.id and p.is_active and not p.is_published
                           and not p.is_ingredient and coalesce(p.sale_price, 0) > 0),
        'with_photo',  (select count(*) from products p
                         where p.org_id = o.id and p.is_active and p.is_published
                           and exists (select 1 from documents d where d.product_id = p.id)),
        'blurb',       nullif(btrim(coalesce(o.storefront_blurb, '')), '') is not null,
        'address',     nullif(btrim(coalesce(o.address, '')), '') is not null,
        'phone',       nullif(btrim(coalesce(o.phone, '')), '') is not null,
        'pin',         o.lat is not null and o.lng is not null
    ) end
    from orgs o where o.id = p_org_id;
$$;

-- 085's street, with the minimum.
create or replace function storefront_directory(
    p_lat double precision default null,
    p_lng double precision default null
)
returns table (
    org_id      uuid,
    name        text,
    slug        text,
    profile     text,
    blurb       text,
    address     text,
    lat         double precision,
    lng         double precision,
    distance_km double precision
)
language sql
stable
security definer
set search_path = public
as $$
    select d.org_id, d.name, d.slug, d.profile, d.blurb, d.address,
           d.lat, d.lng, d.distance_km
    from (
        select o.id as org_id, o.name, o.slug, o.profile::text,
               o.storefront_blurb as blurb, o.address, o.lat, o.lng,
               case
                   when p_lat is null or p_lng is null
                     or o.lat is null or o.lng is null then null
                   else 6371.0 * 2 * asin(sqrt(
                            power(sin(radians(o.lat - p_lat) / 2), 2)
                          + cos(radians(p_lat)) * cos(radians(o.lat))
                          * power(sin(radians(o.lng - p_lng) / 2), 2)))
               end as distance_km
        from orgs o
        where o.storefront_enabled
          and o.archived_at  is null
          and o.suspended_at is null
          and vitrine_items(o.id) >= greatest(cauris_param('vitrine_min_items', 8), 1)
          and (o.progress_since is null
               or vitrine_score(o.id) >= cauris_param('progress_street_pct', 60))
    ) d
    order by (d.distance_km is null), d.distance_km, d.name;
$$;

-- The referral milestone, by itself: the sponsor is paid once the
-- business it brought in has a complete vitrine and 3 finished orders.
create or replace function referral_check(p_org_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_org orgs%rowtype;
begin
    select * into v_org from orgs where id = p_org_id;
    if not found or v_org.referred_by is null then
        return;
    end if;
    if vitrine_score(p_org_id) >= 90
       and (select count(*) from orders o
             where o.org_id = p_org_id and o.status in ('picked_up', 'delivered')) >= 3 then
        perform cauris_award(v_org.referred_by, 'referral', p_org_id::text, v_org.name);
    end if;
end;
$$;

create or replace function trg_referral_check()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.status in ('picked_up', 'delivered')
       and old.status is distinct from new.status then
        perform referral_check(new.org_id);
    end if;
    return new;
end;
$$;

do $$
begin
    if not exists (select 1 from pg_trigger where tgname = 'orders_referral_check') then
        create trigger orders_referral_check after update of status on orders
            for each row execute function trg_referral_check();
    end if;
end $$;

-- 084's milestones, through the same check.
create or replace function cauris_milestones(p_org_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_org orgs%rowtype;
begin
    if not is_org_member(p_org_id) then
        return;
    end if;
    select * into v_org from orgs where id = p_org_id;
    if v_org.storefront_enabled and vitrine_score(p_org_id) >= 100 then
        perform cauris_award(p_org_id, 'vitrine_complete', 'once');
    end if;
    perform referral_check(p_org_id);
end;
$$;

-- 084's wallet, saying what a referral pays and who was sponsored.
create or replace function my_cauris(p_org_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_last timestamptz;
begin
    if not is_org_admin(p_org_id) then
        return null;
    end if;
    perform cauris_expire(p_org_id);
    select max(created_at) into v_last from cauris_ledger
     where org_id = p_org_id and reason <> 'expired';
    return jsonb_build_object(
        'balance', cauris_balance(p_org_id),
        'week', (select coalesce(sum(delta), 0) from cauris_ledger
                  where org_id = p_org_id and delta > 0 and reason <> 'expired'
                    and created_at >= date_trunc('week', now() at time zone 'Africa/Ouagadougou')
                                      at time zone 'Africa/Ouagadougou'),
        'expires_on', case when v_last is null then null
                           else ((v_last at time zone 'Africa/Ouagadougou')::date
                                 + cauris_param('cauris_expire_days', 180)) end,
        'referral_code', (select slug from orgs where id = p_org_id),
        'referred', (select referred_by is not null from orgs where id = p_org_id),
        'referral_points', coalesce((select points from cauris_rules where key = 'referral'), 0),
        'referrals', coalesce((
            select jsonb_agg(jsonb_build_object(
                       'name', r.name,
                       'score', vitrine_score(r.id),
                       'orders', (select count(*) from orders o
                                   where o.org_id = r.id and o.status in ('picked_up', 'delivered')),
                       'paid', exists (select 1 from cauris_ledger l
                                        where l.org_id = p_org_id and l.reason = 'referral'
                                          and l.ref = r.id::text)
                   ) order by r.created_at desc)
              from orgs r where r.referred_by = p_org_id), '[]'::jsonb),
        'history', coalesce((
            select jsonb_agg(jsonb_build_object(
                       'delta', l.delta,
                       'reason', l.reason,
                       'label', coalesce(r.label, case l.reason
                                    when 'expired' then 'Cauris expirés'
                                    when 'spent' then 'Dépensés'
                                    else l.reason end),
                       'note', case when l.reason in ('expired', 'spent', 'prize', 'referral') then l.note end,
                       'at', l.created_at) order by l.created_at desc)
              from (select * from cauris_ledger where org_id = p_org_id
                     order by created_at desc limit 60) l
              left join cauris_rules r on r.key = l.reason), '[]'::jsonb),
        'rules', coalesce((
            select jsonb_agg(jsonb_build_object('key', key, 'points', points,
                       'daily_cap', daily_cap, 'label', label) order by sort)
              from cauris_rules where points > 0), '[]'::jsonb)
    );
end;
$$;

revoke execute on function vitrine_items(uuid)       from public;
revoke execute on function referral_check(uuid)      from public;
revoke execute on function trg_referral_check()      from public;
revoke execute on function storefront_open(text)     from public;
revoke execute on function vitrine_checklist(uuid)   from public;
revoke execute on function storefront_directory(double precision, double precision) from public;
revoke execute on function my_cauris(uuid)           from public;
revoke execute on function cauris_milestones(uuid)   from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function vitrine_items(uuid)     from anon;
        revoke execute on function referral_check(uuid)    from anon;
        revoke execute on function trg_referral_check()    from anon;
        revoke execute on function my_cauris(uuid)         from anon;
        revoke execute on function cauris_milestones(uuid) from anon;
        revoke execute on function vitrine_checklist(uuid) from anon;
        grant execute on function storefront_open(text)    to anon;
        grant execute on function storefront_directory(double precision, double precision) to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke execute on function referral_check(uuid)    from authenticated;
        revoke execute on function trg_referral_check()    from authenticated;
        grant execute on function vitrine_items(uuid)      to authenticated;
        grant execute on function storefront_open(text)    to authenticated;
        grant execute on function vitrine_checklist(uuid)  to authenticated;
        grant execute on function storefront_directory(double precision, double precision) to authenticated;
        grant execute on function my_cauris(uuid)          to authenticated;
        grant execute on function cauris_milestones(uuid)  to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
