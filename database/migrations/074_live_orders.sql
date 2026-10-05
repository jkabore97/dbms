-- ============================================================
-- 074_live_orders.sql — an order reaches the screen when it happens.
--
-- The audit: phones learned of a new order, a courier taking one or a
-- delivery closing only when somebody pulled to refresh (073 added quiet
-- re-reads every minute). Supabase Realtime sends a row's change to every
-- screen subscribed to it, filtered by the same row-level security as a
-- read: the shop's members see their shop's orders, the shopper theirs,
-- the courier those they carry (056's policy). Nothing else changes —
-- the screens re-read through their usual functions when told.
--
-- The publication exists only on Supabase; elsewhere (CI, a local
-- Postgres) this does nothing.
-- ============================================================

do $$
begin
    if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
       and not exists (select 1 from pg_publication_tables
                        where pubname = 'supabase_realtime'
                          and schemaname = 'public' and tablename = 'orders') then
        execute 'alter publication supabase_realtime add table public.orders';
    end if;
end $$;
