-- ============================================================
-- 048_platform_audit.sql — the audit log, across every business.
--
-- 008 gave each business its own activity log, gated by is_org_admin. A
-- platform admin can read any one of them a business at a time, but not the
-- whole platform at once — which is exactly the view moderation needs: "what
-- has been deleted or changed anywhere, lately, and by whom". This adds one
-- read that spans every org, carrying the business name so an event is
-- legible without opening the business, keyset-paged like the per-org page so
-- the log growing at the top while it is read never shows a row twice.
--
-- Platform admin only, and — like the 008 reads — it fails closed by returning
-- nothing to anyone else rather than raising, since the screen above it is
-- itself platform-admin only.
-- ============================================================

create or replace function platform_audit_page(
    p_limit  int    default 50,
    p_before bigint default null,   -- id of the oldest row already shown
    p_org_id uuid   default null,
    p_action text   default null,   -- 'insert' | 'update' | 'delete'
    p_table  text   default null
)
returns table (
    id          bigint,
    at          timestamptz,
    org_id      uuid,
    org_name    text,
    actor_id    uuid,
    actor_label text,
    action      text,
    table_name  text,
    row_id      uuid,
    summary     text
)
language sql
stable
security definer
set search_path = public, auth
as $$
    select l.id, l.at, l.org_id, o.name, l.actor_id, l.actor_label,
           l.action, l.table_name, l.row_id, l.summary
    from audit_log l
    join orgs o on o.id = l.org_id
    where exists (select 1 from profiles
                  where id = auth.uid() and is_platform_admin)
      and (p_before is null or l.id < p_before)
      and (p_org_id is null or l.org_id = p_org_id)
      and (p_action is null or l.action = p_action)
      and (p_table  is null or l.table_name = p_table)
    order by l.id desc
    limit greatest(coalesce(p_limit, 50), 1);
$$;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function platform_audit_page(int, bigint, uuid, text, text)
            to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
