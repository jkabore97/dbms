-- ============================================================
-- 050_platform_people_email_cast.sql — the directory reads email as text.
--
-- platform_people() (047) declares its email column `text` and returns
-- `auth.users.email` straight through. On real Supabase that column is
-- `character varying(255)`, not text, and PL/pgSQL checks the row type of a
-- RETURN QUERY against the declared OUT columns exactly: a varchar where text
-- is declared raises "structure of query does not match function result type"
-- the moment the function runs. The local stub had `auth.users.email` as
-- `text`, so every test passed and the mismatch only surfaced against the real
-- database — which is why the directory came up empty with that error.
--
-- The fix is one cast, `u.email::text`. The stub is tightened to varchar in the
-- same change so the test now reproduces this class of bug instead of hiding
-- it. Nothing else about the function changes.
-- ============================================================

create or replace function platform_people(
    p_query  text default null,
    p_limit  int  default 50,
    p_offset int  default 0
)
returns table (
    user_id           uuid,
    full_name         text,
    phone             text,
    email             text,
    title             text,
    is_platform_admin boolean,
    business_count    bigint,
    created_at        timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_q text := nullif(btrim(coalesce(p_query, '')), '');
begin
    -- Qualified: this function returns a column also named is_platform_admin,
    -- so a bare reference here is ambiguous.
    if not exists (select 1 from profiles
                   where profiles.id = auth.uid()
                     and profiles.is_platform_admin) then
        raise exception 'Only a platform admin can list people';
    end if;

    return query
    select
        p.id,
        p.full_name,
        p.phone,
        u.email::text,  -- auth.users.email is varchar(255) on real Supabase
        p.title,
        p.is_platform_admin,
        (select count(distinct m.org_id) from memberships m where m.user_id = p.id),
        p.created_at
    from profiles p
    join auth.users u on u.id = p.id
    where v_q is null
       or p.full_name ilike '%' || v_q || '%'
       or p.phone     ilike '%' || v_q || '%'
       or u.email     ilike '%' || v_q || '%'
    order by coalesce(p.full_name, u.email, p.phone) nulls last
    limit greatest(1, least(coalesce(p_limit, 50), 200))
    offset greatest(0, coalesce(p_offset, 0));
end;
$$;

notify pgrst, 'reload schema';
