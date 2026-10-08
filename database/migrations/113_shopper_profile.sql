-- ============================================================
-- 113_shopper_profile.sql — the shopper's own page (« Mon compte »), for
-- an account that shops on the street: its orders and bookings, the
-- vitrines it follows, where it gets delivered, how it likes to pay, help,
-- and its data. The owner approved the proposal as written; mobile money
-- is offered only when the platform allows it (RULE M).
--
--   1. shopper_settings: one row per person — the city they shop in, the
--      way they prefer to pay (cash; Wave only while the platform's
--      « Payer en ligne par Wave » switch is on: 076's wave_on(), the one
--      platform-level switch behind « cash only — Wave hidden until
--      admin allows ») and the « nouveautés des vitrines » switch for all
--      the vitrines they follow. Nothing is stored for somebody who never
--      changed anything: the defaults are cash, no city, news on.
--   2. vitrine_follows: « ♥ » on a vitrine (and on its card in the
--      street) follows it. Each follow has its own news switch. When the
--      business puts a NEW article or service on its vitrine (a product
--      becoming active and published there), or lowers the price of one
--      already there (an offer), every follower with news on — and the
--      global switch on — is told by ONE bell row per vitrine per day
--      (Africa/Ouagadougou's day): the first novelty of the day writes the
--      row (so 060's webhook pushes it once), the next ones of the same
--      day rewrite that row « 3 nouveautés chez … : A, B, C… » (an update,
--      so no second push) — for all the followers in one statement, and
--      no more after the twentieth of the day. No scheduler: the coalescing is written when
--      the owner adds the article (trg_vitrine_news), and it never blocks
--      the owner's write (a failure leaves the bell silent, as 030 does).
--      Only what the street can see is said: the vitrine open to the
--      public (storefront_enabled, not archived nor suspended, at its
--      minimum — 092/098/107's rule, unchanged) and the article on it as
--      far as 110's switches go (vitrine_shows). A member of the business
--      is never told about their own vitrine.
--   3. shopper_addresses: Maison / Travail / Autre (one Maison, one
--      Travail, ten addresses in all), each with the words a courier reads
--      first, a note (« portail bleu »), and a pin. The order sheet picks
--      one when the shopper chooses delivery; nothing in place_order (109)
--      changes — the sheet sends the address and the pin as today.
--   4. my_order_basket(order): « Recommander » — what of an order of the
--      caller's is still on that vitrine, at most what is left (101), for
--      the app to put back in the basket.
--   5. problem_reports: « Signaler un problème » — a few words, a topic,
--      optionally the vitrine or the order; five a day per person. The
--      command center counts the open ones in À faire « Signalements »
--      (111's platform_todo reads this table by name, guarded, so 111
--      runs with or without 113); platform_reports() lists them and
--      platform_handle_report() closes one, journaled (105's
--      platform_log_action) with its « Annuler », and tells the person.
--   6. support_whatsapp: the platform's WhatsApp help number, empty as
--      installed — the shopper's « Écrire à Mara sur WhatsApp » is not
--      drawn until Réglages sets it. Digits only (8 to 15, the country's
--      code first), checked whoever writes it.
--   7. my_data_export(): « Télécharger mes données » — the caller's
--      profile, settings, addresses, favourites, orders (with their lines)
--      and reports, as one JSON, nobody else's.
--   8. delete_my_account_check(): « Supprimer mon compte » goes through
--      the existing path — the account Worker, the one holder of the
--      service-role key (044/103) — which asks THIS function, as the
--      caller, whether the account may go, and deletes exactly the id it
--      answers. Refused, in French: a platform account, anybody who
--      belongs to a business (their Compte is the business's), a courier
--      (their file stays with Mara), an order still open, and anybody
--      whose name another table still holds without letting go (a former
--      employee's sales, stock moves, invoices… — every « no action »
--      foreign key to profiles, read from the catalogue: the deletion
--      would fail on it). Deleting the account removes, by the existing
--      cascades, the profile, its bell and this file's rows. The person's
--      ORDERS stay with the shops — the shop's history, its order events,
--      stock moves and the sale of a handed-over order are the shop's
--      books — but without the person: orders.customer_id lets go (« on
--      delete set null », 055's « cascade » would take the sale's order
--      from under it and fail), and profile_gone_orders writes « Client
--      supprimé » over the name and empties the phone, the address and
--      the pin first.
--
-- Shops (retail), farms and associations (and the legacy church): all
-- three are followed, notified and reported alike — the trigger reads the
-- product, not the kind; a farm's articles leave the news when its « À
-- vendre sur la vitrine » is hidden, any kind's services when « Services
-- et réservations » is (110). No business reads or changes anything here;
-- no vitrine shows anything different until somebody follows it (P1).
--
-- Born closed (063): the trigger functions and the helper are internal;
-- each door is for a signed-in person and acts on that person's own rows,
-- or is the platform's (platform_only()). The tables have RLS on and no
-- policies: they are read and written through the functions below.
-- Re-runnable: tables and indexes « if not exists », triggers dropped and
-- recreated, functions replaced with their own signatures, the setting
-- inserted « on conflict do nothing ».
-- ============================================================

do $$
begin
    if to_regprocedure('public.vitrine_shows(uuid, boolean)') is null
       or to_regprocedure('public.my_verified_phone()') is null
       or to_regprocedure('public.platform_log_action(uuid, text, text, jsonb, jsonb, text, jsonb)') is null
       or to_regprocedure('public.vitrine_min(uuid)') is null
       or to_regprocedure('public.wave_on()') is null then
        raise exception '113 needs 076 (wave_on), 104/105 (the journal), 107 (vitrine_min), 109 (my_verified_phone) and 110 (vitrine_shows) applied first';
    end if;
end $$;

-- ------------------------------------------------------------
-- 1. The tables
-- ------------------------------------------------------------
create table if not exists shopper_settings (
    user_id      uuid primary key references profiles(id) on delete cascade,
    city         text check (city is null or char_length(city) between 1 and 60),
    payment      text not null default 'cash' check (payment in ('cash', 'wave')),
    vitrine_news boolean not null default true,
    updated_at   timestamptz not null default now()
);
comment on table shopper_settings is
    'The shopper''s own choices (113): city, preferred payment (Wave only under wave_on()), news from followed vitrines.';
alter table shopper_settings enable row level security;
-- No policies: read and written through the functions below.

create table if not exists vitrine_follows (
    user_id    uuid not null references profiles(id) on delete cascade,
    org_id     uuid not null references orgs(id) on delete cascade,
    news       boolean not null default true,
    created_at timestamptz not null default now(),
    -- The day (Africa/Ouagadougou) this follower was last told about this
    -- vitrine, and the bell row of that day: the next novelty of the same
    -- day rewrites that row rather than writing (and pushing) another.
    told_on    date,
    told_id    uuid,
    primary key (user_id, org_id)
);
create index if not exists vitrine_follows_by_org on vitrine_follows (org_id) where news;
comment on table vitrine_follows is
    'A shopper follows a vitrine (113): told of its new articles and offers, one bell row per vitrine per day.';
alter table vitrine_follows enable row level security;

create table if not exists shopper_addresses (
    id         uuid primary key default gen_random_uuid(),
    user_id    uuid not null references profiles(id) on delete cascade,
    kind       text not null check (kind in ('home', 'work', 'other')),
    label      text check (label is null or char_length(label) between 1 and 40),
    address    text not null check (char_length(address) between 2 and 200),
    note       text check (note is null or char_length(note) between 1 and 200),
    lat        double precision check (lat is null or lat between -90 and 90),
    lng        double precision check (lng is null or lng between -180 and 180),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint shopper_addresses_pin check ((lat is null) = (lng is null))
);
create index if not exists shopper_addresses_by_user on shopper_addresses (user_id);
-- One « Maison », one « Travail »; as many « Autre » as the limit allows.
create unique index if not exists shopper_addresses_one_home_work
    on shopper_addresses (user_id, kind) where kind in ('home', 'work');
comment on table shopper_addresses is
    'Where a shopper is delivered (113): home, work or other, the words, a note and a pin.';
alter table shopper_addresses enable row level security;

create table if not exists problem_reports (
    id          uuid primary key default gen_random_uuid(),
    reporter_id uuid not null references profiles(id) on delete cascade,
    topic       text not null check (topic in ('order', 'vitrine', 'payment', 'delivery', 'app', 'other')),
    message     text not null check (char_length(message) between 10 and 1000),
    org_id      uuid references orgs(id) on delete set null,
    order_id    uuid references orders(id) on delete set null,
    -- How Mara can answer: the proved number, else the profile's, else
    -- the e-mail — as it was when the report was written.
    contact     text,
    status      text not null default 'open' check (status in ('open', 'handled')),
    created_at  timestamptz not null default now(),
    handled_at  timestamptz,
    handled_by  uuid references profiles(id) on delete set null,
    answer      text check (answer is null or char_length(answer) <= 500)
);
create index if not exists problem_reports_open on problem_reports (created_at) where status = 'open';
create index if not exists problem_reports_by_reporter on problem_reports (reporter_id, created_at desc);
comment on table problem_reports is
    '« Signaler un problème » (113): read by the platform (À faire « Signalements »), handled with a journal line.';
alter table problem_reports enable row level security;

-- ------------------------------------------------------------
-- 2. The platform's help number
-- ------------------------------------------------------------
insert into platform_settings (key, value) values ('support_whatsapp', '""')
on conflict (key) do nothing;

-- Digits only once the spaces, the « + » and the dashes are taken out: a
-- wrong number would send every shopper's question to a stranger.
create or replace function trg_support_whatsapp()
returns trigger
language plpgsql
set search_path = public
as $$
declare
    v text := regexp_replace(coalesce(new.value #>> '{}', ''), '[[:space:]+().-]', '', 'g');
begin
    if jsonb_typeof(new.value) <> 'string' or (v <> '' and v !~ '^[0-9]{8,15}$') then
        raise exception 'Le numéro WhatsApp de l''aide : l''indicatif du pays puis le numéro, en chiffres (par exemple 22670000000).';
    end if;
    return new;
end;
$$;

drop trigger if exists support_whatsapp_check on platform_settings;
create trigger support_whatsapp_check
before insert or update on platform_settings
for each row when (new.key = 'support_whatsapp')
execute function trg_support_whatsapp();

-- The number, digits only, or null while the platform has not set one.
create or replace function support_whatsapp()
returns text
language sql
stable
security definer
set search_path = public
as $$
    select nullif(regexp_replace(coalesce((select value #>> '{}' from platform_settings
                                           where key = 'support_whatsapp'), ''),
                                 '[^0-9]', '', 'g'), '');
$$;

-- ------------------------------------------------------------
-- 3. The shopper's page
-- ------------------------------------------------------------
-- The addresses, Maison first, then Travail, then the others by age.
create or replace function my_addresses()
returns jsonb
language sql
stable
security definer
set search_path = public, auth
as $$
    select coalesce(jsonb_agg(jsonb_build_object(
               'id', a.id, 'kind', a.kind, 'label', a.label, 'address', a.address,
               'note', a.note, 'lat', a.lat, 'lng', a.lng)
               order by case a.kind when 'home' then 0 when 'work' then 1 else 2 end,
                        a.created_at), '[]'::jsonb)
      from shopper_addresses a
     where a.user_id = auth.uid();
$$;

-- Everything the page draws, in one question: who (the name, the proved
-- number and the one typed on the profile, the city), the choices, the
-- counts of its rows, the help number, and whether the person is a
-- courier or belongs to a business.
create or replace function my_shopper_profile()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_me  uuid := auth.uid();
    v_out jsonb;
begin
    if v_me is null then
        raise exception 'Connectez-vous d''abord';
    end if;
    select jsonb_build_object(
               'name', coalesce(nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
                                nullif(btrim(coalesce(p.full_name, '')), '')),
               'phone', nullif(btrim(coalesce(p.phone, '')), ''),
               'verified_phone', my_verified_phone(),
               -- 109's switch: the WhatsApp code is set up and asked.
               'verify_on', order_phone_required(),
               'city', s.city,
               -- RULE M: Wave is a choice only while the platform allows it.
               'wave', wave_on(),
               'payment', case when wave_on() then coalesce(s.payment, 'cash') else 'cash' end,
               'news', coalesce(s.vitrine_news, true),
               'support_whatsapp', support_whatsapp(),
               'courier', (select c.status from couriers c where c.user_id = v_me),
               'member', exists (select 1 from memberships m where m.user_id = v_me),
               'addresses', my_addresses(),
               'follows', (select count(*) from vitrine_follows f where f.user_id = v_me),
               'orders_open', (select count(*) from orders o
                                where o.customer_id = v_me
                                  and o.status in ('pending', 'accepted', 'ready', 'in_transit')))
      into v_out
      from profiles p
      left join shopper_settings s on s.user_id = p.id
     where p.id = v_me;
    return v_out;
end;
$$;

-- The choices, any of the three (a key left out is left as it is):
-- {"city": "Ouagadougou", "payment": "cash" | "wave", "news": true}.
create or replace function set_my_shopper_settings(p_patch jsonb)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_me      uuid := auth.uid();
    v_city    text;
    v_payment text;
begin
    if v_me is null then
        raise exception 'Connectez-vous d''abord';
    end if;
    if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
        raise exception 'Rien à enregistrer.';
    end if;
    if p_patch ? 'city' then
        v_city := nullif(btrim(coalesce(p_patch ->> 'city', '')), '');
        if char_length(v_city) > 60 then
            raise exception 'Une ville de 60 caractères au plus.';
        end if;
    end if;
    if p_patch ? 'payment' then
        v_payment := p_patch ->> 'payment';
        if v_payment is null or v_payment not in ('cash', 'wave') then
            raise exception 'Espèces ou Wave.';
        end if;
        if v_payment = 'wave' and not wave_on() then
            raise exception 'Paiement en espèces uniquement pour le moment.';
        end if;
    end if;
    if p_patch ? 'news' and jsonb_typeof(p_patch -> 'news') <> 'boolean' then
        raise exception 'Oui ou non.';
    end if;
    insert into shopper_settings as s (user_id, city, payment, vitrine_news)
    values (v_me, v_city, coalesce(v_payment, 'cash'),
            coalesce((p_patch ->> 'news')::boolean, true))
    on conflict (user_id) do update
       set city         = case when p_patch ? 'city' then v_city else s.city end,
           payment      = case when p_patch ? 'payment' then v_payment else s.payment end,
           vitrine_news = case when p_patch ? 'news' then (p_patch ->> 'news')::boolean
                               else s.vitrine_news end,
           updated_at   = now();
end;
$$;

-- ------------------------------------------------------------
-- 4. Following a vitrine
-- ------------------------------------------------------------
-- ♥ on an open vitrine. Answers the business's id. Following twice is
-- following once (the news switch is kept).
create or replace function follow_vitrine(p_slug text)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_me  uuid := auth.uid();
    v_org uuid;
begin
    if v_me is null then
        raise exception 'Connectez-vous d''abord';
    end if;
    v_org := storefront_open(p_slug);
    if v_org is null then
        raise exception 'Cette vitrine n''est pas ouverte.';
    end if;
    if not exists (select 1 from vitrine_follows where user_id = v_me and org_id = v_org)
       and (select count(*) from vitrine_follows where user_id = v_me) >= 200 then
        raise exception 'Vous suivez déjà 200 vitrines : retirez-en une d''abord.';
    end if;
    insert into vitrine_follows (user_id, org_id) values (v_me, v_org)
    on conflict (user_id, org_id) do nothing;
    return v_org;
end;
$$;

-- ♥ again: no longer followed. By the business's id, so a vitrine that
-- closed (or changed its address) can still be let go.
create or replace function unfollow_vitrine(p_org_id uuid)
returns void
language sql
security definer
set search_path = public, auth
as $$
    delete from vitrine_follows where user_id = auth.uid() and org_id = p_org_id;
$$;

-- One vitrine's news on or off.
create or replace function set_follow_news(p_org_id uuid, p_on boolean)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if auth.uid() is null then
        raise exception 'Connectez-vous d''abord';
    end if;
    update vitrine_follows set news = coalesce(p_on, true)
     where user_id = auth.uid() and org_id = p_org_id;
    if not found then
        raise exception 'Vous ne suivez pas cette vitrine.';
    end if;
end;
$$;

-- The vitrines the caller follows, by name: each with its address, its
-- kind, its logo, whether its news is on and whether it is open today.
create or replace function my_follows()
returns jsonb
language sql
stable
security definer
set search_path = public, auth
as $$
    select coalesce(jsonb_agg(jsonb_build_object(
               'org_id', o.id, 'slug', o.slug, 'name', o.name, 'profile', o.profile::text,
               'logo_key', o.logo_key, 'news', f.news, 'since', f.created_at,
               'open', storefront_open(o.slug) is not null)
               order by lower(o.name)), '[]'::jsonb)
      from vitrine_follows f
      join orgs o on o.id = f.org_id
     where f.user_id = auth.uid();
$$;

-- The bell for the followers (030's rules: never in the way of the
-- owner's write; no scheduler). Fired by a product becoming visible on
-- its vitrine (new) or one already there getting cheaper (an offer).
create or replace function trg_vitrine_news()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_day   date := (now() at time zone 'Africa/Ouagadougou')::date;
    v_offer boolean;
    v_org   orgs%rowtype;
    v_line  text;
    v_rows  uuid[];
    v_users uuid[];
begin
    if not (new.is_active and new.is_published) then
        return new;
    end if;
    if tg_op = 'INSERT' or not (old.is_active and old.is_published) then
        v_offer := false;
    elsif new.sale_price < old.sale_price then
        v_offer := true;
    else
        return new;
    end if;
    -- Nobody follows this business with news on: nothing to read further.
    if not exists (select 1 from vitrine_follows f where f.org_id = new.org_id and f.news) then
        return new;
    end if;
    begin
        select * into v_org from orgs where id = new.org_id;
        -- What the street sees, and only that.
        if not (v_org.storefront_enabled and v_org.archived_at is null
                and v_org.suspended_at is null
                and vitrine_items(v_org.id) >= vitrine_min(v_org.id)
                and vitrine_shows(v_org.id, new.is_service)) then
            return new;
        end if;
        v_line := case when v_offer
            then format('Prix en baisse chez %s : %s à %s %s', v_org.name, new.name,
                        to_char(new.sale_price, 'FM999G999G999'), coalesce(v_org.default_currency, 'XOF'))
            else format('Nouveau chez %s : %s', v_org.name, new.name) end;

        -- Told already today: the day's row says one more — every such
        -- follower in ONE statement (a vitrine with thousands of followers
        -- must not cost the owner a write per follower). After 20
        -- novelties the row is left as it is (« 20 nouveautés chez … :
        -- A, B, C… »): the vitrine shows the rest, and the owner's next
        -- articles of the day cost no rewrite at all.
        update notifications n
           set message = format('%s nouveautés chez %s : %s%s', x.n, v_org.name,
                                (select string_agg(e, ', ') from jsonb_array_elements_text(x.names) e),
                                case when x.n > jsonb_array_length(x.names) then '…' else '' end),
               params  = jsonb_build_object('to', 'customer', 'shop', v_org.name,
                                            'slug', v_org.slug, 'count', x.n,
                                            'names', x.names, 'ids', x.ids || to_jsonb(new.id::text)),
               read_at = null
          from vitrine_follows f
          cross join lateral (
              select coalesce((nn.params ->> 'count')::int, 1) + 1 as n,
                     coalesce(nn.params -> 'ids', '[]'::jsonb) as ids,
                     case when jsonb_array_length(coalesce(nn.params -> 'names', '[]'::jsonb)) < 3
                               and not coalesce(nn.params -> 'names', '[]'::jsonb) ? new.name
                          then coalesce(nn.params -> 'names', '[]'::jsonb) || to_jsonb(new.name)
                          else coalesce(nn.params -> 'names', '[]'::jsonb) end as names
                from notifications nn where nn.id = f.told_id
          ) x
         where f.org_id = new.org_id and f.news and f.told_on = v_day
           and n.id = f.told_id
           and not exists (select 1 from shopper_settings s
                            where s.user_id = f.user_id and not s.vitrine_news)
           -- At most 20; the same article twice the same day is said once.
           and coalesce((n.params ->> 'count')::int, 1) < 20
           and not coalesce(n.params -> 'ids', '[]'::jsonb) ? new.id::text;

        -- Not told today: one row each (060's webhook pushes it once). The
        -- day is claimed first, row by row, so two writes at once never
        -- tell the same follower twice.
        with fresh as (
            update vitrine_follows f
               set told_on = v_day, told_id = null
             where f.org_id = new.org_id and f.news
               and f.told_on is distinct from v_day
               and not exists (select 1 from shopper_settings s
                                where s.user_id = f.user_id and not s.vitrine_news)
               and not exists (select 1 from memberships m
                                where m.org_id = f.org_id and m.user_id = f.user_id)
            returning f.user_id
        ), told as (
            insert into notifications (recipient_id, org_id, kind, message, params)
            select fresh.user_id, new.org_id, 'vitrine_news', v_line,
                   jsonb_build_object('to', 'customer', 'shop', v_org.name, 'slug', v_org.slug,
                                      'count', 1, 'names', jsonb_build_array(new.name),
                                      'ids', jsonb_build_array(new.id::text),
                                      'offer', v_offer, 'price', new.sale_price,
                                      'currency', coalesce(v_org.default_currency, 'XOF'))
              from fresh
            returning id, recipient_id
        )
        select coalesce(array_agg(told.id), '{}'), coalesce(array_agg(told.recipient_id), '{}')
          into v_rows, v_users
          from told;
        -- The day's row, for the next novelty of the day (a statement of
        -- its own: a row is changed once per statement).
        update vitrine_follows f set told_id = t.nid
          from unnest(v_rows, v_users) as t(nid, uid)
         where f.user_id = t.uid and f.org_id = new.org_id;
    exception when others then
        -- Books beat bells (030): the article is saved whatever happens here.
        null;
    end;
    return new;
end;
$$;

drop trigger if exists vitrine_news on products;
create trigger vitrine_news
after insert or update of is_active, is_published, sale_price on products
for each row execute function trg_vitrine_news();

-- ------------------------------------------------------------
-- 5. Where to deliver
-- ------------------------------------------------------------
-- A new address (p_id null) or one of the caller's changed. Answers its id.
create or replace function save_my_address(
    p_id      uuid,
    p_kind    text,
    p_label   text,
    p_address text,
    p_note    text,
    p_lat     double precision,
    p_lng     double precision
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_me      uuid := auth.uid();
    v_id      uuid;
    v_label   text := nullif(btrim(coalesce(p_label, '')), '');
    v_address text := nullif(btrim(coalesce(p_address, '')), '');
    v_note    text := nullif(btrim(coalesce(p_note, '')), '');
begin
    if v_me is null then
        raise exception 'Connectez-vous d''abord';
    end if;
    if p_kind is null or p_kind not in ('home', 'work', 'other') then
        raise exception 'Maison, travail ou autre.';
    end if;
    if v_address is null or char_length(v_address) < 2 then
        raise exception 'Dites où livrer : le quartier, un repère.';
    end if;
    if char_length(v_address) > 200 or char_length(v_note) > 200 then
        raise exception 'Une adresse et une note de 200 caractères au plus.';
    end if;
    if char_length(v_label) > 40 then
        raise exception 'Un nom de 40 caractères au plus.';
    end if;
    if (p_lat is null) <> (p_lng is null)
       or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
        raise exception 'Cette position n''est pas valable.';
    end if;
    if exists (select 1 from shopper_addresses
                where user_id = v_me and kind = p_kind and p_kind in ('home', 'work')
                  and id is distinct from p_id) then
        raise exception '%', case p_kind
            when 'home' then 'Vous avez déjà une adresse « Maison » : modifiez-la.'
            else 'Vous avez déjà une adresse « Travail » : modifiez-la.' end;
    end if;
    if p_id is null then
        if (select count(*) from shopper_addresses where user_id = v_me) >= 10 then
            raise exception 'Dix adresses au plus : retirez-en une d''abord.';
        end if;
        insert into shopper_addresses (user_id, kind, label, address, note, lat, lng)
        values (v_me, p_kind, case when p_kind = 'other' then v_label end,
                v_address, v_note, p_lat, p_lng)
        returning id into v_id;
    else
        update shopper_addresses
           set kind = p_kind, label = case when p_kind = 'other' then v_label end,
               address = v_address, note = v_note, lat = p_lat, lng = p_lng,
               updated_at = now()
         where id = p_id and user_id = v_me
        returning id into v_id;
        if v_id is null then
            raise exception 'Adresse introuvable.';
        end if;
    end if;
    return v_id;
end;
$$;

create or replace function delete_my_address(p_id uuid)
returns void
language sql
security definer
set search_path = public, auth
as $$
    delete from shopper_addresses where id = p_id and user_id = auth.uid();
$$;

-- ------------------------------------------------------------
-- 6. « Recommander »
-- ------------------------------------------------------------
-- What of one of the caller's orders that vitrine still has, for the
-- basket: each article or service still on it (the street's own shelf:
-- open, active, published, shown by 110's switches, in stock or to come),
-- at most what is left of an article. « closed »: the vitrine takes no
-- orders now (110), nothing to put back. « missing »: the lines left out.
create or replace function my_order_basket(p_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_order orders%rowtype;
    v_slug  text;
    v_open  uuid;
    v_lines jsonb;
    v_total int;
begin
    if auth.uid() is null then
        raise exception 'Connectez-vous d''abord';
    end if;
    select * into v_order from orders where id = p_order_id and customer_id = auth.uid();
    if not found then
        raise exception 'Commande introuvable.';
    end if;
    select slug into v_slug from orgs where id = v_order.org_id;
    v_open := storefront_open(v_slug);
    select count(*) into v_total from order_lines where order_id = p_order_id;
    if v_open is null or feature_hidden(v_open, 'online_orders') then
        return jsonb_build_object('slug', v_slug, 'closed', true,
                                  'lines', '[]'::jsonb, 'missing', v_total);
    end if;
    select coalesce(jsonb_agg(jsonb_build_object('product_id', x.product_id, 'quantity', x.quantity)
                              order by x.name), '[]'::jsonb)
      into v_lines
      from (
        select p.id as product_id, p.name,
               case when p.is_service
                      or p.available_from > (now() at time zone 'Africa/Ouagadougou')::date
                    then sum(l.quantity)
                    -- What is left, as it is (0.5 kg is half a kilo to sell,
                    -- not nothing): 101's storefront_stock caps the basket
                    -- the same way, and place_order takes up to it.
                    else least(sum(l.quantity), p.quantity) end as quantity
          from order_lines l
          join products p on p.id = l.product_id
         where l.order_id = p_order_id
           and p.org_id = v_open
           and p.is_active and p.is_published
           and vitrine_shows(p.org_id, p.is_service)
           and (p.is_service or p.quantity > 0
                or p.available_from > (now() at time zone 'Africa/Ouagadougou')::date)
         group by p.id, p.name, p.is_service, p.available_from, p.quantity
      ) x
     where x.quantity > 0;
    return jsonb_build_object('slug', v_slug, 'closed', false, 'lines', v_lines,
                              'missing', v_total - jsonb_array_length(v_lines));
end;
$$;

-- ------------------------------------------------------------
-- 7. « Signaler un problème »
-- ------------------------------------------------------------
create or replace function report_problem(
    p_topic    text,
    p_message  text,
    p_slug     text default null,
    p_order_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_me      uuid := auth.uid();
    v_message text := btrim(coalesce(p_message, ''));
    v_org     uuid;
    v_id      uuid;
begin
    if v_me is null then
        raise exception 'Connectez-vous d''abord';
    end if;
    if p_topic is null or p_topic not in ('order', 'vitrine', 'payment', 'delivery', 'app', 'other') then
        raise exception 'Choisissez de quoi il s''agit.';
    end if;
    if char_length(v_message) < 10 then
        raise exception 'Dites en quelques mots ce qui ne va pas (10 caractères au moins).';
    end if;
    if char_length(v_message) > 1000 then
        raise exception 'Un message de 1 000 caractères au plus.';
    end if;
    if (select count(*) from problem_reports
         where reporter_id = v_me and created_at > now() - interval '24 hours') >= 5 then
        raise exception 'Vous avez déjà envoyé 5 signalements aujourd''hui : Mara les lit et vous répond.';
    end if;
    if p_order_id is not null then
        select org_id into v_org from orders where id = p_order_id and customer_id = v_me;
        if not found then
            raise exception 'Commande introuvable.';
        end if;
    elsif nullif(btrim(coalesce(p_slug, '')), '') is not null then
        select id into v_org from orgs where slug = lower(btrim(p_slug));
    end if;
    insert into problem_reports (reporter_id, topic, message, org_id, order_id, contact)
    values (v_me, p_topic, v_message, v_org, p_order_id,
            coalesce(my_verified_phone(),
                     (select nullif(btrim(coalesce(phone, '')), '') from profiles where id = v_me),
                     (select email from auth.users where id = v_me)))
    returning id into v_id;
    return v_id;
end;
$$;

-- The platform's list: the open ones first and oldest first (what waits
-- longest is read first), or the handled ones, newest first.
create or replace function platform_reports(p_status text default 'open')
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_rows jsonb;
begin
    perform platform_only();
    if p_status is null or p_status not in ('open', 'handled') then
        raise exception 'Liste inconnue : %', coalesce(p_status, '');
    end if;
    select coalesce(jsonb_agg(x.r order by
                       case when p_status = 'open' then x.at end asc,
                       case when p_status = 'handled' then x.at end desc), '[]'::jsonb)
      into v_rows
      from (
        select r.created_at as at, jsonb_build_object(
                   'id', r.id, 'topic', r.topic, 'message', r.message, 'at', r.created_at,
                   'status', r.status, 'contact', r.contact,
                   'reporter', coalesce(nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
                                        nullif(btrim(coalesce(p.full_name, '')), '')),
                   'org_id', r.org_id, 'org_name', o.name, 'slug', o.slug,
                   'order_id', r.order_id, 'answer', r.answer, 'handled_at', r.handled_at) as r
          from problem_reports r
          left join profiles p on p.id = r.reporter_id
          left join orgs o on o.id = r.org_id
         where r.status = p_status
         order by case when p_status = 'open' then r.created_at end asc,
                  case when p_status = 'handled' then r.created_at end desc
         limit 200
      ) x;
    return v_rows;
end;
$$;

-- One report closed, with the platform's answer (optional): journaled
-- with its « Annuler », and the person told.
create or replace function platform_handle_report(p_id uuid, p_answer text default null)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_r      problem_reports%rowtype;
    v_answer text := nullif(btrim(coalesce(p_answer, '')), '');
begin
    perform platform_only();
    if char_length(v_answer) > 500 then
        raise exception 'Une réponse de 500 caractères au plus.';
    end if;
    select * into v_r from problem_reports where id = p_id for update;
    if not found then
        raise exception 'Signalement introuvable.';
    end if;
    if v_r.status = 'handled' then
        raise exception 'Ce signalement est déjà traité.';
    end if;
    update problem_reports
       set status = 'handled', handled_at = now(), handled_by = auth.uid(), answer = v_answer
     where id = p_id;
    begin
        insert into notifications (recipient_id, org_id, kind, message, params)
        values (v_r.reporter_id, null, 'report_handled',
                case when v_answer is null then 'Mara a traité votre signalement. Merci !'
                     else 'Mara a traité votre signalement : ' || v_answer end,
                -- The facts (099): the app says it in the reader's language.
                jsonb_build_object('to', 'customer', 'answer', v_answer));
    exception when others then
        null;
    end;
    return platform_log_action(
        v_r.org_id, 'report',
        'Signalement traité : ' || left(v_r.message, 80),
        jsonb_build_object('status', 'open'),
        jsonb_build_object('status', 'handled', 'answer', v_answer),
        'platform_undo_report',
        jsonb_build_object('id', p_id));
end;
$$;

-- « Annuler »: the report open again (the person's notice stays said).
create or replace function platform_undo_report(p_args jsonb)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    perform platform_only();
    update problem_reports
       set status = 'open', handled_at = null, handled_by = null, answer = null
     where id = (p_args ->> 'id')::uuid and status = 'handled';
    if not found then
        raise exception 'Ce signalement a changé depuis.';
    end if;
end;
$$;

insert into platform_undo_fns (fn) values ('platform_undo_report')
on conflict do nothing;

-- ------------------------------------------------------------
-- 8. « Mes données »
-- ------------------------------------------------------------
create or replace function my_data_export()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_me uuid := auth.uid();
begin
    if v_me is null then
        raise exception 'Connectez-vous d''abord';
    end if;
    return jsonb_build_object(
        'exported_at', now(),
        'profile', (select jsonb_build_object(
                        'first_name', p.first_name, 'middle_name', p.middle_name,
                        'last_name', p.last_name, 'full_name', p.full_name,
                        'title', p.title, 'date_of_birth', p.date_of_birth,
                        'phone', p.phone, 'verified_phone', my_verified_phone(),
                        'email', u.email, 'language', p.preferred_locale,
                        'created_at', p.created_at)
                      from profiles p left join auth.users u on u.id = p.id
                     where p.id = v_me),
        'settings', (select jsonb_build_object('city', s.city, 'payment', s.payment,
                                               'vitrine_news', s.vitrine_news)
                       from shopper_settings s where s.user_id = v_me),
        'addresses', my_addresses(),
        'favourites', (select coalesce(jsonb_agg(jsonb_build_object(
                                 'vitrine', o.name, 'address', 'marakaj.com/s/' || o.slug,
                                 'news', f.news, 'since', f.created_at) order by f.created_at), '[]'::jsonb)
                         from vitrine_follows f join orgs o on o.id = f.org_id
                        where f.user_id = v_me),
        'orders', (select coalesce(jsonb_agg(jsonb_build_object(
                             'vitrine', g.name, 'placed_at', o.created_at, 'status', o.status,
                             'fulfilment', o.fulfilment, 'address', o.address, 'phone', o.phone,
                             'note', o.note, 'payment', o.payment_method, 'paid_at', o.paid_at,
                             'total', o.total, 'delivery_fee', o.delivery_fee, 'currency', o.currency,
                             'lines', (select coalesce(jsonb_agg(jsonb_build_object(
                                                 'name', l.name, 'quantity', l.quantity,
                                                 'unit_price', l.unit_price,
                                                 'service', l.is_service) order by l.name), '[]'::jsonb)
                                         from order_lines l where l.order_id = o.id))
                             order by o.created_at), '[]'::jsonb)
                     from orders o join orgs g on g.id = o.org_id
                    where o.customer_id = v_me),
        'reports', (select coalesce(jsonb_agg(jsonb_build_object(
                              'topic', r.topic, 'message', r.message, 'at', r.created_at,
                              'status', r.status, 'answer', r.answer) order by r.created_at), '[]'::jsonb)
                      from problem_reports r where r.reporter_id = v_me));
end;
$$;

-- The orders stay with the shop, without the person (see the header):
-- the column lets go of a deleted profile instead of taking the order
-- with it. Re-runnable: the constraint is dropped and made again.
alter table orders alter column customer_id drop not null;
alter table orders drop constraint if exists orders_customer_id_fkey;
alter table orders add constraint orders_customer_id_fkey
    foreign key (customer_id) references profiles(id) on delete set null;

-- Before the profile goes (GoTrue's delete of auth.users cascades here,
-- whoever asked it — the person or an admin): the name, the phone, the
-- address and the pin of that person's orders are gone too. The order
-- itself, its lines, events, stock moves and sale stay the shop's.
create or replace function trg_profile_gone_orders()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    update orders
       set customer_name = 'Client supprimé', phone = null, address = null,
           drop_lat = null, drop_lng = null
     where customer_id = old.id;
    return old;
end;
$$;

drop trigger if exists profile_gone_orders on profiles;
create trigger profile_gone_orders
before delete on profiles
for each row execute function trg_profile_gone_orders();

-- « Supprimer mon compte »: asked by the account Worker as the caller
-- (workers/account-admin, POST /v1/me/delete). Answers the caller's own
-- id when the account may go; refuses in French otherwise. It deletes
-- nothing itself: the Worker deletes exactly the id answered, with the
-- service-role key, and the cascades take the rest.
--
-- The last refusal reads the catalogue: every foreign key to profiles
-- that neither cascades nor lets go (« no action » / « restrict ») would
-- make GoTrue's delete fail, so a row there holds the account. As
-- installed (113) they are: accounts, crop_cycles, customers,
-- debt_payments, debts, egg_production, employees, flock_events, flocks,
-- harvests, herd_events, herds, invoice_payments, invoices, items,
-- journal_entries, plots, products, stock_movements, tontine_contributions,
-- tontines .created_by; documents.uploaded_by; employees.user_id;
-- orders.courier_id (said above, as a courier's); org_currency_rates and
-- org_feature_rules .updated_by; pending_invitations .created_by and
-- .claimed_by; plan_requests .user_id and .handled_by; production_runs,
-- sales and shifts .recorded_by; promotions .decided_by and
-- .requested_by; staff_payments.paid_by; stock_receipts .received_by and
-- .reversed_by — a former employee's work, mostly. A key added later is
-- read the same way, with no change here.
create or replace function delete_my_account_check()
returns uuid
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_me   uuid := auth.uid();
    v_held boolean;
    r      record;
begin
    if v_me is null then
        raise exception 'Connectez-vous d''abord';
    end if;
    if exists (select 1 from profiles where id = v_me and is_platform_admin) then
        raise exception 'Un compte de la plateforme ne se supprime pas ici.';
    end if;
    if exists (select 1 from memberships where user_id = v_me) then
        raise exception 'Vous faites partie d''une activité sur Mara : votre compte se supprime une fois que vous n''en faites plus partie.';
    end if;
    if exists (select 1 from couriers where user_id = v_me)
       or exists (select 1 from orders where courier_id = v_me) then
        raise exception 'Vous êtes livreur sur Mara : écrivez à Mara pour fermer votre compte livreur.';
    end if;
    if exists (select 1 from orders where customer_id = v_me
                 and status in ('pending', 'accepted', 'ready', 'in_transit')) then
        raise exception 'Une commande est en cours : attendez qu''elle soit terminée, ou annulez-la, puis supprimez votre compte.';
    end if;
    for r in
        select c.conrelid::regclass as tbl, a.attname as col
          from pg_constraint c
          join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
         where c.contype = 'f'
           and c.confrelid = 'public.profiles'::regclass
           and c.confdeltype in ('a', 'r')
           and cardinality(c.conkey) = 1
         order by 1, 2
    loop
        execute format('select exists (select 1 from %s where %I = $1)', r.tbl, r.col)
           into v_held using v_me;
        if v_held then
            raise exception 'Votre nom reste sur ce que vous avez inscrit pour une activité sur Mara (ventes, stock, factures…) : écrivez à Mara pour fermer votre compte.';
        end if;
    end loop;
    return v_me;
end;
$$;

-- ------------------------------------------------------------
-- Grants: born closed (063); each opened to whom it is for.
-- ------------------------------------------------------------
revoke execute on function trg_support_whatsapp()          from public;
revoke execute on function support_whatsapp()              from public;
revoke execute on function my_addresses()                  from public;
revoke execute on function my_shopper_profile()            from public;
revoke execute on function set_my_shopper_settings(jsonb)  from public;
revoke execute on function follow_vitrine(text)            from public;
revoke execute on function unfollow_vitrine(uuid)          from public;
revoke execute on function set_follow_news(uuid, boolean)  from public;
revoke execute on function my_follows()                    from public;
revoke execute on function trg_vitrine_news()              from public;
revoke execute on function save_my_address(uuid, text, text, text, text, double precision, double precision) from public;
revoke execute on function delete_my_address(uuid)         from public;
revoke execute on function my_order_basket(uuid)           from public;
revoke execute on function report_problem(text, text, text, uuid) from public;
revoke execute on function platform_reports(text)          from public;
revoke execute on function platform_handle_report(uuid, text) from public;
revoke execute on function platform_undo_report(jsonb)     from public;
revoke execute on function my_data_export()                from public;
revoke execute on function delete_my_account_check()       from public;
revoke execute on function trg_profile_gone_orders()       from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function trg_support_whatsapp()          from anon;
        revoke execute on function support_whatsapp()              from anon;
        revoke execute on function my_addresses()                  from anon;
        revoke execute on function my_shopper_profile()            from anon;
        revoke execute on function set_my_shopper_settings(jsonb)  from anon;
        revoke execute on function follow_vitrine(text)            from anon;
        revoke execute on function unfollow_vitrine(uuid)          from anon;
        revoke execute on function set_follow_news(uuid, boolean)  from anon;
        revoke execute on function my_follows()                    from anon;
        revoke execute on function trg_vitrine_news()              from anon;
        revoke execute on function save_my_address(uuid, text, text, text, text, double precision, double precision) from anon;
        revoke execute on function delete_my_address(uuid)         from anon;
        revoke execute on function my_order_basket(uuid)           from anon;
        revoke execute on function report_problem(text, text, text, uuid) from anon;
        revoke execute on function platform_reports(text)          from anon;
        revoke execute on function platform_handle_report(uuid, text) from anon;
        revoke execute on function platform_undo_report(jsonb)     from anon;
        revoke execute on function my_data_export()                from anon;
        revoke execute on function delete_my_account_check()       from anon;
        revoke execute on function trg_profile_gone_orders()       from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        -- Internal: the triggers, and what the doors below read as their
        -- owner (the undo, through 104's platform_undo).
        revoke execute on function trg_support_whatsapp()          from authenticated;
        revoke execute on function trg_vitrine_news()              from authenticated;
        revoke execute on function trg_profile_gone_orders()       from authenticated;
        revoke execute on function my_addresses()                  from authenticated;
        revoke execute on function platform_undo_report(jsonb)     from authenticated;
        -- The doors: a signed-in person and their own rows — the help
        -- number too (business Compte's « Contacter le support »)...
        grant execute on function support_whatsapp()               to authenticated;
        grant execute on function my_shopper_profile()             to authenticated;
        grant execute on function set_my_shopper_settings(jsonb)   to authenticated;
        grant execute on function follow_vitrine(text)             to authenticated;
        grant execute on function unfollow_vitrine(uuid)           to authenticated;
        grant execute on function set_follow_news(uuid, boolean)   to authenticated;
        grant execute on function my_follows()                     to authenticated;
        grant execute on function save_my_address(uuid, text, text, text, text, double precision, double precision) to authenticated;
        grant execute on function delete_my_address(uuid)          to authenticated;
        grant execute on function my_order_basket(uuid)            to authenticated;
        grant execute on function report_problem(text, text, text, uuid) to authenticated;
        grant execute on function my_data_export()                 to authenticated;
        grant execute on function delete_my_account_check()        to authenticated;
        -- ...and the platform's, each checking platform_only().
        grant execute on function platform_reports(text)           to authenticated;
        grant execute on function platform_handle_report(uuid, text) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
