-- ============================================================
-- 187 — Mara's message to everyone.
--
-- The owner: « make sure that if I send notification for app update,
-- everyone will receive it. » The console's message (072, 115) reached the
-- owners and admins of each business — or their whole teams — and nobody
-- else: of 68 accounts, the 26 in a business. The shoppers, the guests,
-- the couriers with no business heard nothing.
--
--   * platform_message_send (115): a third audience, 'everyone' — every
--     account, in its bell (the row is the account's own, shown in every
--     list: params.to = 'me', no business), and so pushed to each of its
--     phones and browsers like any bell. « Marakaj : … ».
--   * platform_message_reach(): how many accounts each audience reaches,
--     and how many of them have a phone or browser to push to — said in
--     the console before sending.
--   * The two audiences of before verbatim.
--
-- Shop, farm, association: their owners and teams are accounts too — they
-- hear it once each, as everyone.
-- ============================================================

create or replace function platform_message_send(
    p_org_id   uuid,
    p_message  text,
    p_audience text
)
returns integer
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_text     text := nullif(btrim(coalesce(p_message, '')), '');
    v_audience text := coalesce(nullif(btrim(coalesce(p_audience, '')), ''), 'admins');
    v_count    integer;
begin
    if not caller_is_platform_admin() then
        raise exception 'Seule la plateforme écrit aux boutiques';
    end if;
    if v_text is null then
        raise exception 'Le message est vide';
    end if;
    if length(v_text) > 500 then
        raise exception 'Un message tient en 500 caractères';
    end if;
    if v_audience not in ('admins', 'team', 'everyone') then
        raise exception 'Destinataires inconnus : %', v_audience;
    end if;
    if v_audience = 'everyone' then
        -- every account, once — its own row, in every one of its lists
        insert into notifications (recipient_id, org_id, kind, message, params)
        select p.id, null, 'platform_message', 'Marakaj : ' || v_text,
               jsonb_build_object('to', 'me', 'text', v_text, 'audience', 'everyone')
          from profiles p
          join auth.users u on u.id = p.id;
        get diagnostics v_count = row_count;
        return v_count;
    end if;
    insert into notifications (recipient_id, org_id, kind, message, params)
    select distinct m.user_id, m.org_id, 'platform_message', 'Kaj : ' || v_text,
           jsonb_build_object('to', 'shop', 'text', v_text, 'audience', v_audience)
      from memberships m
      join orgs o on o.id = m.org_id
     where (v_audience = 'team' or m.role in ('owner', 'super_admin', 'admin'))
       and o.archived_at is null
       and (p_org_id is null or m.org_id = p_org_id);
    get diagnostics v_count = row_count;
    return v_count;
end;
$$;

-- How far each audience goes, before sending: accounts, and those of them
-- with a phone or a browser that takes pushes.
create or replace function platform_message_reach()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    if not caller_is_platform_admin() then
        raise exception 'Seule la plateforme écrit aux boutiques';
    end if;
    return jsonb_build_object(
        'everyone', (select count(*) from profiles p join auth.users u on u.id = p.id),
        'everyone_push', (select count(distinct s.user_id) from push_subscriptions s
                            join profiles p on p.id = s.user_id),
        'admins', (select count(distinct m.user_id) from memberships m join orgs o on o.id = m.org_id
                    where o.archived_at is null and m.role in ('owner', 'super_admin', 'admin')),
        'team', (select count(distinct m.user_id) from memberships m join orgs o on o.id = m.org_id
                  where o.archived_at is null));
end;
$$;

-- 186's sections: the message's
insert into platform_rpc_sections (fn, sections) values
    ('platform_message_reach', '{today,clients}')
on conflict (fn) do update set sections = excluded.sections;

revoke execute on function platform_message_reach() from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function platform_message_reach() from anon;
        revoke execute on function platform_message_send(uuid, text, text) from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function platform_message_reach() to authenticated;
        grant execute on function platform_message_send(uuid, text, text) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
