-- ============================================================
-- 127_security_fixes.sql — the security audit's fixes (A2, schema 126).
--
--   1. Team. A membership row is written only by the flows that mean it:
--      an invitation claimed by the person it names (claim_invitation,
--      claim_my_invitations), a business opened (create_org,
--      approve_org_application, showcase_join), a trainer named by the
--      platform (assign_trainer). Each is a definer function; none passes
--      through a policy. So the app's own doors are closed: no INSERT and
--      no UPDATE policy on memberships any more (100 let a business admin
--      insert a row for any user_id, then manage — reset the password of —
--      whoever it named). set_membership_role and revoke_membership stay
--      the doors for a role and a removal. A row never changes hands
--      (user_id, org_id fixed), and its scope belongs to its business.
--      An invitation is never written as already claimed by an admin.
--      The sign-in sweep (claim_my_invitations) claims by a proved number
--      only an invitation older than the account; otherwise the code.
--      manages_user (the Worker's password reset, admin_save_member_profile,
--      can_delete_user) asks what can_delete_user asked: the person belongs
--      to no business the caller does not administer. Never a platform
--      admin, as before. sign_out_member (it only closes sessions) keeps
--      103's rule, as outranks_member.
--   2. documents. r2_key starts with org/<the row's org_id>/ (a showcase's
--      own showcase/… keys aside), on every signed-in write (a trigger);
--      orgs.logo_key and the vitrine's cover_key follow the same rule;
--      a courier file's key under courier/<its user>/.
--      storefront_photo_allowed never serves a key under another business's
--      folder, so a row written before 127 that pointed there serves nothing.
--   3. Ledger. A line joins an entry only in the transaction that wrote the
--      entry; a line never changes; an entry never changes (delete_org's
--      unlinking of a reversal aside). Corrections are reverse_entry /
--      reverse_entry_by_client_uuid, as before. A line's account belongs to
--      the entry's business — and, generally, every reference from a
--      business's row to another business-owned row stays inside the
--      business (trg_same_org, on every child table the audit listed).
--   4. The delivery code. Five wrong codes for one order lock it for 15
--      minutes and tell the shop; the third lock is for good (the shop
--      ends the order itself, « Livrée au client », or the courier
--      reports « Échec »). courier_handover(order, code) answers
--      {ok, reason, left, minutes, message} instead of raising on a wrong
--      code — a raise would roll the count back with it. courier_deliver
--      keeps its signature for the app already installed (void; a wrong
--      code now counts, and returns without delivering).
--   5. security_log(user, kind, detail) is no app door: closed to
--      authenticated (it let anybody write into anybody's « Sécurité »).
--
-- Shop, farm and association alike: memberships, documents, the ledger and
-- the security log are shared by all three. The delivery code concerns the
-- businesses that deliver (shops and farms on a vitrine). Nothing that the
-- app does through its own functions changes (test_batch127, P1).
--
-- Re-runnable (the bundle runs twice): create or replace, drop … if exists,
-- constraints and tables if not exists.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Team
-- ------------------------------------------------------------
drop policy if exists "memberships granted by org admins" on memberships;
drop policy if exists "memberships amended by org admins" on memberships;
-- 103 took the grant back too; a project that handed it again (Supabase's
-- defaults) loses it again.
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke insert, update, truncate on memberships from authenticated;
    end if;
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke insert, update, delete, truncate on memberships from anon;
    end if;
end $$;

-- The holder and the business of a grant never change, by anybody; its
-- scope (an entity, a department) is one of its own business's.
create or replace function scope_in_org(p_kind scope_kind, p_scope uuid, p_org uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select case p_kind
        when 'org'        then p_scope = p_org
        when 'entity'     then exists (select 1 from entities e
                                        where e.id = p_scope and e.org_id = p_org)
        when 'department' then exists (select 1 from departments d
                                         join entities e on e.id = d.entity_id
                                        where d.id = p_scope and e.org_id = p_org)
        else false
    end;
$$;

create or replace function trg_membership_holder()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if tg_op = 'UPDATE'
       and (new.user_id is distinct from old.user_id
            or new.org_id is distinct from old.org_id) then
        raise exception 'Un accès ne passe pas à une autre personne ni à une autre entreprise'
            using errcode = 'insufficient_privilege';
    end if;
    if (tg_op = 'INSERT' or new.scope_kind is distinct from old.scope_kind
                         or new.scope_id   is distinct from old.scope_id)
       and not scope_in_org(new.scope_kind, new.scope_id, new.org_id) then
        raise exception 'Cette portée appartient à une autre entreprise'
            using errcode = 'check_violation';
    end if;
    return new;
end;
$$;

drop trigger if exists membership_holder on memberships;
create trigger membership_holder
before insert or update on memberships
for each row execute function trg_membership_holder();

create or replace function trg_invitation_scope()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if (tg_op = 'INSERT' or new.scope_kind is distinct from old.scope_kind
                         or new.scope_id   is distinct from old.scope_id
                         or new.org_id     is distinct from old.org_id)
       and not scope_in_org(new.scope_kind, new.scope_id, new.org_id) then
        raise exception 'Cette portée appartient à une autre entreprise'
            using errcode = 'check_violation';
    end if;
    return new;
end;
$$;

drop trigger if exists invitation_scope on pending_invitations;
create trigger invitation_scope
before insert or update on pending_invitations
for each row execute function trg_invitation_scope();

-- An admin writes and amends an open invitation; only the claim (definer)
-- marks it claimed, by the person who claimed it.
drop policy if exists "invitations issued by org admins" on pending_invitations;
create policy "invitations issued by org admins"
on pending_invitations for insert
with check (
    is_org_admin(org_id) and created_by = auth.uid()
    and claimed_at is null and claimed_by is null
);

drop policy if exists "unclaimed invitations amended by org admins" on pending_invitations;
create policy "unclaimed invitations amended by org admins"
on pending_invitations for update
using (is_org_admin(org_id) and claimed_at is null)
with check (is_org_admin(org_id) and claimed_at is null and claimed_by is null);

-- 103's, plus can_delete_user's rule: never someone who also belongs to a
-- business the caller does not administer (a password, a profile, a
-- sign-out are the whole account's, not one business's).
create or replace function manages_user(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    select case
        when auth.uid() is null or p_user_id is null or p_user_id = auth.uid() then false
        -- The platform's own people are managed by nobody from here.
        when exists (select 1 from profiles where id = p_user_id and is_platform_admin) then false
        when caller_is_platform_admin() then true
        -- The owner is the top of a business, and an owner anywhere is
        -- nobody's to reset from another business either.
        when exists (select 1 from memberships where user_id = p_user_id and role = 'owner') then false
        when exists (select 1 from profiles where id = p_user_id and is_trainer) then false
        -- 127: somebody with a place in a business the caller does not
        -- administer is not the caller's to manage.
        when exists (select 1 from memberships t
                      where t.user_id = p_user_id and not is_org_admin(t.org_id)) then false
        else exists (
            select 1
              from memberships me
             where me.user_id = auth.uid()
               and not me.is_trainer
               and me.role in ('owner', 'super_admin', 'admin')
               and me.org_id in (select t.org_id from memberships t
                                  where t.user_id = p_user_id and not t.is_trainer)
               and role_rank(me.role) > (
                   select coalesce(max(role_rank(t.role)), 0)
                     from memberships t where t.user_id = p_user_id))
    end;
$$;

-- The sign-in sweep (103's). A number is handed on when a line is given up,
-- so a proved number claims by itself only an invitation sent before the
-- account existed: the account was made for it. An account older than the
-- invitation (the number may have been somebody else's before) claims it
-- with its code, claim_invitation, as everybody does today. The e-mail
-- path is unchanged.
create or replace function claim_my_invitations()
returns integer
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_uid     uuid := auth.uid();
    v_phone   text;
    v_email   text;
    v_created timestamptz;
    v_count   int := 0;
    v_inv     pending_invitations%rowtype;
begin
    if v_uid is null then
        return 0;
    end if;

    if not exists (select 1 from profiles where id = v_uid) then
        return 0;
    end if;

    -- Only what auth.users itself holds as confirmed (103).
    select case when u.phone_confirmed_at is not null then u.phone end,
           case when u.email_confirmed_at is not null then u.email end,
           u.created_at
      into v_phone, v_email, v_created
      from auth.users u where u.id = v_uid;

    for v_inv in
        select * from pending_invitations i
        where i.claimed_at is null
          and i.expires_at > now()
          and (
              (v_phone is not null and i.phone = v_phone
               and v_created is not null and v_created >= i.created_at)
              or (v_email is not null and lower(i.email) = lower(v_email))
          )
        for update
    loop
        begin
            insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility)
            values (v_inv.org_id, v_uid, v_inv.role, v_inv.scope_kind,
                    v_inv.scope_id, v_inv.visibility)
            on conflict (user_id, scope_kind, scope_id, role) do nothing;
        exception when raise_exception or insufficient_privilege then
            continue;  -- no seat, or a grant only the platform makes (100)
        end;

        update pending_invitations
        set claimed_at = now(), claimed_by = v_uid
        where id = v_inv.id and claimed_at is null;

        v_count := v_count + 1;
    end loop;

    return v_count;
end;
$$;

-- A sign-out only closes sessions: it stays with 103's rule (someone below
-- the caller in one of the caller's businesses, never the platform, an
-- owner or a trainer), even for a clerk who also works elsewhere.
create or replace function outranks_member(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    select case
        when auth.uid() is null or p_user_id is null or p_user_id = auth.uid() then false
        when exists (select 1 from profiles where id = p_user_id and is_platform_admin) then false
        when caller_is_platform_admin() then true
        when exists (select 1 from memberships where user_id = p_user_id and role = 'owner') then false
        when exists (select 1 from profiles where id = p_user_id and is_trainer) then false
        else exists (
            select 1
              from memberships me
             where me.user_id = auth.uid()
               and not me.is_trainer
               and me.role in ('owner', 'super_admin', 'admin')
               and me.org_id in (select t.org_id from memberships t
                                  where t.user_id = p_user_id and not t.is_trainer)
               and role_rank(me.role) > (
                   select coalesce(max(role_rank(t.role)), 0)
                     from memberships t where t.user_id = p_user_id))
    end;
$$;

create or replace function sign_out_member(p_org_id uuid, p_user_id uuid)
returns integer
language plpgsql
security definer
set search_path = public, auth
as $$
declare v_rows int;
begin
    if not is_org_admin(p_org_id) then
        raise exception 'Seul un administrateur peut déconnecter un membre';
    end if;
    if p_user_id = auth.uid() then
        raise exception 'Pour vous-même : Compte › Sécurité';
    end if;
    if not exists (select 1 from memberships
                    where org_id = p_org_id and user_id = p_user_id and not is_trainer) then
        raise exception 'Cette personne n''est pas membre de l''entreprise';
    end if;
    if exists (select 1 from memberships
                where user_id = p_user_id and org_id = p_org_id
                  and role in ('owner', 'super_admin')) then
        raise exception 'Le propriétaire ne peut pas être déconnecté par un autre';
    end if;
    if not outranks_member(p_user_id) then
        raise exception 'Vous ne pouvez déconnecter que quelqu''un en dessous de vous';
    end if;
    delete from auth.sessions where user_id = p_user_id;
    get diagnostics v_rows = row_count;
    perform security_log(p_user_id, 'signed_out_by_admin',
        (select name from orgs where id = p_org_id));
    return v_rows;
end;
$$;

-- ------------------------------------------------------------
-- 2. Keys: a business's objects live under org/<its id>/
-- ------------------------------------------------------------
create or replace function key_is_orgs(p_key text, p_org uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select p_key is null
        or (p_org is not null and starts_with(p_key, 'org/' || p_org::text || '/'))
        -- 094's example vitrines carry their photos under showcase/.
        or (starts_with(p_key, 'showcase/')
            and exists (select 1 from orgs where id = p_org and showcase));
$$;

-- A key that names another business's folder (org/<another id>/…). The
-- keys the app writes always carry the full id (record_document, 013).
create or replace function key_names_other_org(p_key text, p_org uuid)
returns boolean
language sql
immutable
set search_path = public
as $$
    select coalesce(
        p_key ~* '^org/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/'
        and lower(split_part(p_key, '/', 2)) is distinct from p_org::text,
        false);
$$;

create or replace function trg_document_key()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    -- No signed-in person: the platform itself (its SQL, a service key),
    -- as 069's guard on the same table.
    if auth.uid() is null then
        return new;
    end if;
    if (tg_op = 'INSERT' or new.r2_key is distinct from old.r2_key
                         or new.org_id is distinct from old.org_id)
       and not key_is_orgs(new.r2_key, new.org_id) then
        raise exception 'Cette photo n''est pas un fichier de cette entreprise'
            using errcode = 'check_violation';
    end if;
    return new;
end;
$$;

drop trigger if exists document_key on documents;
create trigger document_key
before insert or update on documents
for each row execute function trg_document_key();

create or replace function trg_org_keys()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if auth.uid() is null then
        return new;
    end if;
    -- The same rule as a documents row (key_is_orgs): the business's own
    -- folder, or showcase/ for an example vitrine. set_org_logo and
    -- set_storefront_style already take a key only from a documents row
    -- of the business, so they pass; this also holds a direct write.
    if (tg_op = 'INSERT' or new.logo_key is distinct from old.logo_key)
       and not key_is_orgs(new.logo_key, new.id) then
        raise exception 'Le logo doit être une photo de cette entreprise'
            using errcode = 'check_violation';
    end if;
    if (tg_op = 'INSERT'
        or new.storefront_style ->> 'cover_key' is distinct from old.storefront_style ->> 'cover_key')
       and not key_is_orgs(new.storefront_style ->> 'cover_key', new.id) then
        raise exception 'La photo de couverture doit être une photo de cette entreprise'
            using errcode = 'check_violation';
    end if;
    return new;
end;
$$;

drop trigger if exists org_keys on orgs;
create trigger org_keys
before insert or update of logo_key, storefront_style on orgs
for each row execute function trg_org_keys();

-- A courier's photo under their own folder (112 wrote it so; now held).
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'courier_file_key_is_theirs') then
        alter table courier_files add constraint courier_file_key_is_theirs
            check (user_id is null or starts_with(r2_key, 'courier/' || user_id::text || '/'))
            not valid;
        begin
            alter table courier_files validate constraint courier_file_key_is_theirs;
        exception when check_violation then
            raise notice '127: a courier file names another folder — the constraint holds for new rows only';
        end;
    end if;
end $$;

-- A row written before 127 pointing at another business's object would
-- be refused today; it is also never served to the street.
create or replace function storefront_photo_allowed(p_key text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    -- Never a key under another business's folder, whatever row names it.
    select exists (
        select 1
        from documents d
        join products p on p.id = d.product_id
        join orgs     o on o.id = p.org_id
        where d.r2_key = p_key
          and p.org_id = d.org_id
          and not key_names_other_org(p_key, d.org_id)
          and doc_is_photo(d.kind, d.content_type)
          and p.is_active
          and p.is_published
          and vitrine_shows(p.org_id, p.is_service)
          and o.storefront_enabled
          and o.archived_at  is null
          and o.suspended_at is null
    ) or exists (
        select 1
        from orgs o
        where o.storefront_style ->> 'cover_key' = p_key
          and not key_names_other_org(p_key, o.id)
          and o.storefront_enabled
          and o.archived_at  is null
          and o.suspended_at is null
          and (vitrine_plus_on(o.id)
               or cauris_param('vitrine_free_basics', 1) = 1)
    ) or exists (
        select 1
        from orgs o
        where o.logo_key = p_key
          and not key_names_other_org(p_key, o.id)
          and o.storefront_enabled
          and o.archived_at  is null
          and o.suspended_at is null
    );
$$;

-- ------------------------------------------------------------
-- 3. The ledger, and references that stay inside their business
-- ------------------------------------------------------------
-- True when the row whose xmin this is was written by the transaction
-- running now (or one of its subtransactions). A row of another
-- transaction still open is invisible, so « in progress » is ours.
create or replace function row_is_this_transactions(p_xmin xid)
returns boolean
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
    v_now  bigint := pg_current_xact_id()::text::bigint;
    v_diff bigint := p_xmin::text::bigint - (v_now & 4294967295);
begin
    if v_diff > 2147483647 then
        v_diff := v_diff - 4294967296;
    elsif v_diff < -2147483648 then
        v_diff := v_diff + 4294967296;
    end if;
    return pg_xact_status((v_now + v_diff)::text::xid8) = 'in progress';
exception when others then
    return false;
end;
$$;

-- A posted entry is closed: a line is added only with its entry, in the
-- same transaction, and never changed afterwards. No signed-in person
-- (the platform's SQL, a service key) is not held.
create or replace function trg_journal_line_closed()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare v_xmin xid;
begin
    if auth.uid() is null then
        return new;
    end if;
    if tg_op = 'UPDATE' then
        raise exception 'Une écriture passée ne se modifie pas : annulez-la (contre-passation) et saisissez-la à nouveau'
            using errcode = 'insufficient_privilege';
    end if;
    select xmin into v_xmin from journal_entries where id = new.journal_entry_id;
    if found and not row_is_this_transactions(v_xmin) then
        raise exception 'Une écriture passée ne se complète pas : annulez-la (contre-passation) et saisissez-la à nouveau'
            using errcode = 'insufficient_privilege';
    end if;
    return new;
end;
$$;

drop trigger if exists journal_line_closed on journal_lines;
create trigger journal_line_closed
before insert or update on journal_lines
for each row execute function trg_journal_line_closed();

create or replace function trg_journal_entry_closed()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if auth.uid() is null then
        return new;
    end if;
    -- delete_org (014) unlinks the reversals before it deletes the books.
    if new.reverses_entry_id is null
       and (to_jsonb(new) - 'reverses_entry_id') = (to_jsonb(old) - 'reverses_entry_id') then
        return new;
    end if;
    raise exception 'Une écriture passée ne se modifie pas : annulez-la (contre-passation) et saisissez-la à nouveau'
        using errcode = 'insufficient_privilege';
end;
$$;

drop trigger if exists journal_entry_closed on journal_entries;
create trigger journal_entry_closed
before update on journal_entries
for each row execute function trg_journal_entry_closed();

-- The business a row of a business-owned table belongs to.
create or replace function org_of_row(p_table text, p_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare v uuid;
begin
    if p_id is null then
        return null;
    end if;
    if p_table = 'departments' then
        select e.org_id into v from departments d join entities e on e.id = d.entity_id
         where d.id = p_id;
    else
        execute format('select org_id from public.%I where id = $1', p_table) into v using p_id;
    end if;
    return v;
end;
$$;

-- Arguments: 'column:parent_table', one per reference. The row's own
-- org_id (when it has one) and every parent's business must be one.
-- Cost: one primary-key lookup per reference, on an insert or on an update
-- that changes org_id or a referencing column (none otherwise) — about
-- 60 µs a row per reference here (50k inserts: 3.7 s against 0.8 s
-- without). Nothing at the app's scale; a bulk import feels it.
create or replace function trg_same_org()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_new    jsonb := to_jsonb(new);
    v_old    jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) end;
    v_org    uuid  := (v_new ->> 'org_id')::uuid;
    v_parent uuid;
    v_col    text;
    v_tab    text;
    i        int;
    v_moved  boolean := tg_op = 'INSERT' or (v_new -> 'org_id') is distinct from (v_old -> 'org_id');
begin
    if not v_moved then
        for i in 0 .. tg_nargs - 1 loop
            v_col := split_part(tg_argv[i], ':', 1);
            if (v_new -> v_col) is distinct from (v_old -> v_col) then
                v_moved := true;
                exit;
            end if;
        end loop;
        if not v_moved then
            return new;
        end if;
    end if;
    for i in 0 .. tg_nargs - 1 loop
        v_col := split_part(tg_argv[i], ':', 1);
        v_tab := split_part(tg_argv[i], ':', 2);
        v_parent := org_of_row(v_tab, (v_new ->> v_col)::uuid);
        continue when v_parent is null;   -- no reference, or the FK refuses it
        if v_org is null then
            v_org := v_parent;
        elsif v_parent <> v_org then
            raise exception 'Cette fiche renvoie à une autre entreprise'
                using errcode = 'check_violation',
                      detail = tg_table_name || '.' || v_col;
        end if;
    end loop;
    return new;
end;
$$;

do $$
declare
    r record;
begin
    for r in select * from (values
        ('journal_entries',          array['entity_id:entities', 'department_id:departments', 'reverses_entry_id:journal_entries']),
        ('journal_lines',            array['journal_entry_id:journal_entries', 'account_id:accounts']),
        ('documents',                array['linked_journal_entry_id:journal_entries', 'product_id:products']),
        ('contribution_attributions',array['journal_entry_id:journal_entries', 'member_id:church_members']),
        ('stock_movements',          array['item_id:items', 'journal_entry_id:journal_entries']),
        ('flocks',                   array['entity_id:entities']),
        ('egg_production',           array['flock_id:flocks']),
        ('invoices',                 array['customer_id:customers', 'journal_entry_id:journal_entries']),
        ('invoice_payments',         array['invoice_id:invoices', 'journal_entry_id:journal_entries']),
        ('sales',                    array['entry_id:journal_entries', 'order_id:orders', 'reverses_id:sales']),
        ('sale_lines',               array['sale_id:sales', 'product_id:products']),
        ('employees',                array['entity_id:entities', 'department_id:departments']),
        ('shifts',                   array['employee_id:employees']),
        ('staff_payments',           array['employee_id:employees', 'entry_id:journal_entries']),
        ('stock_receipts',           array['entry_id:journal_entries', 'product_id:products']),
        ('herds',                    array['entity_id:entities']),
        ('herd_events',              array['herd_id:herds']),
        ('plots',                    array['entity_id:entities']),
        ('crop_cycles',              array['plot_id:plots']),
        ('harvests',                 array['crop_cycle_id:crop_cycles', 'product_id:products']),
        ('debts',                    array['customer_id:customers', 'journal_entry_id:journal_entries', 'sale_id:sales']),
        ('debt_payments',            array['debt_id:debts', 'journal_entry_id:journal_entries']),
        ('tontine_members',          array['tontine_id:tontines']),
        ('tontine_contributions',    array['member_id:tontine_members', 'tontine_id:tontines']),
        ('production_runs',          array['product_id:products']),
        ('production_inputs',        array['run_id:production_runs', 'product_id:products']),
        ('storefront_visits',        array['product_id:products']),
        ('promotions',               array['product_id:products']),
        ('wave_payments',            array['order_id:orders', 'promotion_id:promotions']),
        ('order_lines',              array['order_id:orders', 'product_id:products']),
        ('order_stock_moves',        array['order_id:orders', 'product_id:products']),
        ('problem_reports',          array['order_id:orders'])
    ) t(tab, refs)
    loop
        if to_regclass('public.' || r.tab) is null then
            continue;
        end if;
        execute format('drop trigger if exists same_org on public.%I', r.tab);
        execute format('create trigger same_org before insert or update on public.%I '
                       'for each row execute function trg_same_org(%s)',
                       r.tab, (select string_agg(quote_literal(x), ', ') from unnest(r.refs) x));
    end loop;
end $$;

-- ------------------------------------------------------------
-- 4. The delivery code: five wrong codes lock the order 15 minutes;
--    the third lock is for good
-- ------------------------------------------------------------
create table if not exists handover_guards (
    order_id     uuid primary key references orders(id) on delete cascade,
    failures     integer not null default 0,
    locked_until timestamptz,
    updated_at   timestamptz not null default now()
);
alter table handover_guards add column if not exists lockouts integer not null default 0;
alter table handover_guards enable row level security;
revoke all on handover_guards from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke all on handover_guards from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke all on handover_guards from authenticated;
    end if;
end $$;

comment on table handover_guards is
    'The wrong delivery codes of an order (127): five lock it for 15 '
    'minutes; the third lock (15 wrong codes) is for good (locked_until '
    '= infinity) — the code no longer closes it. Written only by '
    'courier_handover; no policy, no grant.';

-- {ok: true} — delivered.
-- {ok: false, reason: 'wrong_code', left: n, message} — a wrong code, counted.
-- {ok: false, reason: 'locked', minutes: m, message} — a code tried while
--   locked; with fresh: true, the fifth wrong code (the shop is told).
-- {ok: false, reason: 'locked', blocked: true, message} — the third lock:
--   for good. Nobody resets it, by design (no new door, no new screen):
--   the code is spent. The shop is told « bloquée — appelez le livreur »
--   and ends it with what it already has — it calls the customer, then
--   confirms « Livrée au client » itself (decide_order, in_transit →
--   delivered), or the courier reports « Échec » (courier_fail) and brings
--   the parcel back.
-- Raises as before for an order that is not the courier's or not on its
-- way. A wrong code does not raise: the raise would undo its count.
create or replace function courier_handover(p_order_id uuid, p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v       orders%rowtype;
    v_shop  text;
    v_guard handover_guards%rowtype;
    v_fails integer;
    v_locks integer;
    v_min   integer;
    v_blocked_msg constant text :=
        'Trop de codes faux : cette livraison est bloquée. Appelez la boutique.';
begin
    -- for update: two attempts at once count as two.
    select * into v from orders where id = p_order_id for update;
    if not found or v.courier_id is distinct from auth.uid() then
        raise exception 'Cette livraison n''est pas la vôtre';
    end if;
    if v.status <> 'in_transit' then
        raise exception 'Cette livraison n''est pas en route';
    end if;

    select * into v_guard from handover_guards where order_id = p_order_id;
    if v_guard.locked_until = 'infinity' then
        return jsonb_build_object('ok', false, 'reason', 'locked', 'blocked', true,
            'message', v_blocked_msg);
    end if;
    if v_guard.locked_until > now() then
        v_min := greatest(1, ceil(extract(epoch from v_guard.locked_until - now()) / 60)::int);
        return jsonb_build_object('ok', false, 'reason', 'locked', 'minutes', v_min,
            'message', 'Trop de codes faux : cette livraison est bloquée encore ' || v_min
                       || ' min. La boutique est prévenue.');
    end if;

    if v.handover_code is not null
       and btrim(coalesce(p_code, '')) <> v.handover_code then
        v_fails := coalesce(v_guard.failures, 0) + 1;
        if v_fails >= 5 then
            v_locks := coalesce(v_guard.lockouts, 0) + 1;
            insert into handover_guards (order_id, failures, lockouts, locked_until, updated_at)
            values (p_order_id, 0, v_locks,
                    case when v_locks >= 3 then 'infinity'::timestamptz
                         else now() + interval '15 minutes' end, now())
            on conflict (order_id) do update
               set failures = 0, lockouts = excluded.lockouts,
                   locked_until = excluded.locked_until, updated_at = now();
            begin
                if v_locks >= 3 then
                    perform notify_org_admins(v.org_id, 'delivery_code_blocked',
                        'Livraison de ' || v.customer_name
                            || ' : bloquée — appelez le livreur. Trop de codes faux : '
                            || 'le code ne la fermera plus. Après avoir appelé le client, '
                            || 'confirmez « Livrée au client » ou laissez le livreur la déclarer en échec.',
                        jsonb_build_object('to', 'shop', 'order_id', v.id, 'name', v.customer_name));
                else
                    perform notify_org_admins(v.org_id, 'delivery_code_locked',
                        'Livraison de ' || v.customer_name
                            || ' : 5 codes faux, bloquée 15 min. Appelez le livreur ou le client.',
                        jsonb_build_object('to', 'shop', 'order_id', v.id, 'name', v.customer_name,
                                           'minutes', 15));
                end if;
            exception when others then null;
            end;
            if v_locks >= 3 then
                return jsonb_build_object('ok', false, 'reason', 'locked', 'blocked', true,
                    'fresh', true, 'message', v_blocked_msg);
            end if;
            return jsonb_build_object('ok', false, 'reason', 'locked', 'minutes', 15, 'fresh', true,
                'message', 'Trop de codes faux : cette livraison est bloquée 15 min. La boutique est prévenue.');
        end if;
        insert into handover_guards (order_id, failures, updated_at)
        values (p_order_id, v_fails, now())
        on conflict (order_id) do update set failures = v_fails, updated_at = now();
        return jsonb_build_object('ok', false, 'reason', 'wrong_code', 'left', 5 - v_fails,
            'message', 'Code incorrect : demandez au client les 4 chiffres de sa commande ('
                       || (5 - v_fails) || ' essai' || case when 5 - v_fails > 1 then 's' else '' end
                       || ' avant blocage).');
    end if;

    delete from handover_guards where order_id = p_order_id;
    update orders set status = 'delivered', updated_at = now() where id = p_order_id;
    select name into v_shop from orgs where id = v.org_id;
    begin
        insert into notifications (recipient_id, org_id, kind, message, params)
        values (v.customer_id, v.org_id, 'order_delivered',
                'Votre commande chez ' || v_shop || ' est livrée',
                jsonb_build_object('to', 'customer', 'order_id', v.id, 'shop', v_shop));
        perform notify_org_admins(v.org_id, 'order_delivered',
            'La commande de ' || v.customer_name || ' est livrée',
            jsonb_build_object('to', 'shop', 'order_id', v.id, 'name', v.customer_name));
    exception when others then null;
    end;
    return jsonb_build_object('ok', true);
end;
$$;

-- The app already installed calls this one and reads no answer: a wrong
-- code is counted and the delivery stays open (its list shows it still on
-- the way); a locked or blocked order is said, as a refusal (the call
-- that locks it returns, so its count stands).
create or replace function courier_deliver(p_order_id uuid, p_code text)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare v jsonb;
begin
    v := courier_handover(p_order_id, p_code);
    if v ->> 'reason' = 'locked' and v -> 'fresh' is null then
        raise exception '%', v ->> 'message';
    end if;
end;
$$;

-- ------------------------------------------------------------
-- 5. Grants
-- ------------------------------------------------------------
revoke execute on function scope_in_org(scope_kind, uuid, uuid)  from public;
revoke execute on function outranks_member(uuid)                 from public;
revoke execute on function trg_membership_holder()               from public;
revoke execute on function trg_invitation_scope()                from public;
revoke execute on function key_is_orgs(text, uuid)               from public;
revoke execute on function key_names_other_org(text, uuid)       from public;
revoke execute on function trg_document_key()                    from public;
revoke execute on function trg_org_keys()                        from public;
revoke execute on function row_is_this_transactions(xid)         from public;
revoke execute on function trg_journal_line_closed()             from public;
revoke execute on function trg_journal_entry_closed()            from public;
revoke execute on function org_of_row(text, uuid)                from public;
revoke execute on function trg_same_org()                        from public;
revoke execute on function courier_handover(uuid, text)          from public;
revoke execute on function security_log(uuid, text, text)        from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function scope_in_org(scope_kind, uuid, uuid)  from anon;
        revoke execute on function outranks_member(uuid)                 from anon;
        revoke execute on function trg_membership_holder()               from anon;
        revoke execute on function trg_invitation_scope()                from anon;
        revoke execute on function key_is_orgs(text, uuid)               from anon;
        revoke execute on function key_names_other_org(text, uuid)       from anon;
        revoke execute on function trg_document_key()                    from anon;
        revoke execute on function trg_org_keys()                        from anon;
        revoke execute on function row_is_this_transactions(xid)         from anon;
        revoke execute on function trg_journal_line_closed()             from anon;
        revoke execute on function trg_journal_entry_closed()            from anon;
        revoke execute on function org_of_row(text, uuid)                from anon;
        revoke execute on function trg_same_org()                        from anon;
        revoke execute on function courier_handover(uuid, text)          from anon;
        revoke execute on function security_log(uuid, text, text)        from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke execute on function scope_in_org(scope_kind, uuid, uuid)  from authenticated;
        revoke execute on function outranks_member(uuid)                 from authenticated;
        revoke execute on function trg_membership_holder()               from authenticated;
        revoke execute on function trg_invitation_scope()                from authenticated;
        revoke execute on function key_is_orgs(text, uuid)               from authenticated;
        revoke execute on function key_names_other_org(text, uuid)       from authenticated;
        revoke execute on function trg_document_key()                    from authenticated;
        revoke execute on function trg_org_keys()                        from authenticated;
        revoke execute on function row_is_this_transactions(xid)         from authenticated;
        revoke execute on function trg_journal_line_closed()             from authenticated;
        revoke execute on function trg_journal_entry_closed()            from authenticated;
        revoke execute on function org_of_row(text, uuid)                from authenticated;
        revoke execute on function trg_same_org()                        from authenticated;
        -- Called by the definer functions that write the security log
        -- (sign-in, devices, sessions, sign_out_member); no app door.
        revoke execute on function security_log(uuid, text, text)        from authenticated;
        grant  execute on function courier_handover(uuid, text)          to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
