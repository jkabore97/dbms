-- ============================================================
-- 132_admin_today.sql — batch 135: « Aujourd'hui »'s two numbers the
-- owner asked for.
--
-- The owner, on the folded admin center: « Nouveaux comptes » (the new
-- accounts this week) and today's orders at the top of « Aujourd'hui ».
-- No count existed for either: 072's platform_today counts the orders of
-- the last seven days and the businesses, platform_overview the new
-- businesses — never an account, never today.
--
--   platform_today_counts() → jsonb, or null for anybody but a platform
--   admin (guarded exactly as 072's platform_today: the caller's profile
--   says is_platform_admin, else null — no error, no number):
--     accounts_week       accounts made in the last 7 days (auth.users,
--                         as 047's platform_people and 129's bell read
--                         them: one row per account, whatever its way in);
--     accounts_last_week  the 7 days before those;
--     orders_today        orders placed since midnight in Ouagadougou
--                         (072's clock), every status;
--     orders_last_week    orders placed on the same day last week, from
--                         its midnight to the same hour — so the morning
--                         is never set against a whole day;
--     day_start           today's midnight, as an instant.
--
-- SECURITY DEFINER with a pinned search path, as platform_today and
-- platform_overview are: auth.users is readable by its owner alone, and
-- the platform's orders are every business's (no member's RLS shows them
-- all). It reads counts only — no name, no e-mail, no number leaves.
-- Closed to PUBLIC and anon (063's rule), open to authenticated, whose
-- non-admins get null.
--
-- Platform-level: the same for a shop, a farm and an association —
-- nothing a business, a vitrine or a member sees changes. An app without
-- 132 behind it draws « Aujourd'hui » as batch 135 first did (the new
-- businesses of the week, the orders over seven days).
-- Run twice, it changes nothing (create or replace; grants re-said).
-- ============================================================

create or replace function public.platform_today_counts()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_day  timestamptz := date_trunc('day', now() at time zone 'Africa/Ouagadougou')
                          at time zone 'Africa/Ouagadougou';
    v_week timestamptz := now() - interval '7 days';
begin
    if not exists (select 1 from public.profiles
                    where id = auth.uid() and is_platform_admin) then
        return null;
    end if;

    return jsonb_build_object(
        'accounts_week',      (select count(*) from auth.users
                                where created_at >= v_week),
        'accounts_last_week', (select count(*) from auth.users
                                where created_at >= v_week - interval '7 days'
                                  and created_at <  v_week),
        'orders_today',       (select count(*) from public.orders
                                where created_at >= v_day),
        'orders_last_week',   (select count(*) from public.orders
                                where created_at >= v_day - interval '7 days'
                                  and created_at <  now() - interval '7 days'),
        'day_start',          v_day
    );
end;
$$;

revoke execute on function public.platform_today_counts() from public;
do $$ begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function public.platform_today_counts() from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function public.platform_today_counts() to authenticated;
    end if;
end $$;
