-- ============================================================
-- 118_invitation_salary.sql — « Équipe », one question a screen (batch 115,
-- W3): the salary said when the person is invited, for a shop, a farm and
-- an association alike.
--
-- Before this, a salary could only be written once the person had joined
-- (100's set_member_salary needs a member). The new « Ajouter une
-- personne » flow asks it with the rest — name, phone, responsibility,
-- what they see — so the invitation carries it until it is claimed:
--
--   1. pending_invitations.salary / salary_period: nothing for every
--      invitation written before (P1: the claim of an older invitation
--      does exactly what it did).
--   2. set_invitation_salary(invitation, amount, period): the inviter's
--      door (103 revoked UPDATE on the table). An unclaimed invitation of
--      a business the caller administers, and 103's salary rule: the owner
--      (or the platform) for any invitation, another admin only for a
--      responsibility below their own — an invitation is already below
--      the inviter's (103's invite_employee), so the inviter can always
--      say it. 0 clears it. Never an owner's invitation.
--   3. trg_invitation_salary: when the invitation is claimed (by
--      claim_invitation or the sign-in sweep — every claim writes
--      claimed_at), the person's payroll row gets the salary exactly as
--      set_member_salary writes it (their own row, else an unlinked one of
--      the same name, else a new permanent row), written as the inviter.
--      A row paid by the hour is left as it is. It never stands in the way
--      of the claim: a failure leaves the salary unwritten, the person in.
--      Never one's own salary (103): nothing is written when the claimer
--      wrote the invitation, or was already in the business before the
--      claim.
--
-- No app path changes for anybody who does not use the new flow.
-- ============================================================

alter table pending_invitations add column if not exists salary numeric(14,2);
alter table pending_invitations add column if not exists salary_period text;

do $$
begin
    if not exists (select 1 from pg_constraint
                    where conname = 'invitation_salary_sane') then
        alter table pending_invitations add constraint invitation_salary_sane
            check ((salary is null and salary_period is null)
                   or (salary > 0 and salary <= 1000000000
                       and salary_period in ('month', 'week', 'day')));
    end if;
end $$;

create or replace function set_invitation_salary(
    p_invitation_id uuid,
    p_amount        numeric,
    p_period        text default 'month'
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_inv    pending_invitations%rowtype;
    v_amount numeric := coalesce(p_amount, 0);
    v_period text := coalesce(nullif(btrim(coalesce(p_period, '')), ''), 'month');
begin
    if auth.uid() is null then
        raise exception 'Connectez-vous d''abord';
    end if;
    select * into v_inv from pending_invitations where id = p_invitation_id;
    if not found or not is_org_admin(v_inv.org_id) then
        raise exception 'Seul un administrateur note le salaire de l''équipe';
    end if;
    if v_inv.claimed_at is not null then
        raise exception 'Cette invitation a déjà été utilisée : le salaire se change dans Équipe';
    end if;
    if v_inv.role = 'owner' then
        raise exception 'Seul le propriétaire, ou quelqu''un au-dessus de cette personne, note son salaire';
    end if;
    if not is_org_owner(v_inv.org_id) and not caller_is_platform_admin()
       and org_rank_of(v_inv.org_id, auth.uid()) <= role_rank(v_inv.role) then
        raise exception 'Seul le propriétaire, ou quelqu''un au-dessus de cette personne, note son salaire';
    end if;
    if v_amount < 0 or v_amount > 1000000000 then
        raise exception 'Le salaire doit être un montant positif';
    end if;
    if v_period not in ('month', 'week', 'day') then
        raise exception 'Période inconnue : %', v_period;
    end if;

    update pending_invitations
       set salary        = case when v_amount = 0 then null else v_amount end,
           salary_period = case when v_amount = 0 then null else v_period end
     where id = p_invitation_id;
end;
$$;

create or replace function trg_invitation_salary()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_row   employees%rowtype;
    v_name  text;
    v_phone text;
begin
    -- 103 forbids saying one's own salary. An invitation one wrote oneself,
    -- or one claimed by somebody already in the business before this claim
    -- (an admin who put their own number on it), carries none: the salary
    -- of a member is said in Équipe, by someone above them.
    if new.claimed_by is not distinct from new.created_by
       or exists (select 1 from memberships m
                   where m.org_id = new.org_id
                     and m.user_id = new.claimed_by
                     and m.created_at < transaction_timestamp()) then
        return new;
    end if;

    begin
        select person_name(new.claimed_by), phone into v_name, v_phone
          from profiles where id = new.claimed_by;
        v_name := coalesce(v_name, new.full_name, 'Membre');

        select * into v_row from employees
         where org_id = new.org_id and user_id = new.claimed_by
         order by is_active desc, created_at limit 1;
        if v_row.id is null then
            select * into v_row from employees
             where org_id = new.org_id and user_id is null
               and lower(btrim(full_name)) = lower(btrim(v_name))
             order by is_active desc, created_at limit 1;
        end if;

        if v_row.id is null then
            if exists (select 1 from employees
                        where org_id = new.org_id
                          and lower(btrim(full_name)) = lower(btrim(v_name))) then
                v_name := v_name || ' (' || coalesce(v_phone, left(new.claimed_by::text, 8)) || ')';
            end if;
            insert into employees (org_id, full_name, phone, kind, salary, pay_period,
                                   user_id, created_by)
            values (new.org_id, v_name, v_phone, 'permanent', new.salary,
                    new.salary_period, new.claimed_by, new.created_by);
        elsif v_row.kind = 'permanent' then
            update employees
               set user_id    = new.claimed_by,
                   is_active  = true,
                   ended_on   = null,
                   end_reason = null,
                   salary     = new.salary,
                   pay_period = new.salary_period
             where id = v_row.id;
        end if;
    exception when others then
        null;  -- the person is in; the salary can still be said in Équipe
    end;
    return new;
end;
$$;

drop trigger if exists invitation_salary on pending_invitations;
create trigger invitation_salary
    after update of claimed_at on pending_invitations
    for each row
    when (old.claimed_at is null and new.claimed_at is not null
          and new.salary is not null)
    execute function trg_invitation_salary();

revoke execute on function set_invitation_salary(uuid, numeric, text) from public;
revoke execute on function trg_invitation_salary()                     from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function set_invitation_salary(uuid, numeric, text) from anon;
        revoke execute on function trg_invitation_salary()                     from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke execute on function trg_invitation_salary()                     from authenticated;
        grant  execute on function set_invitation_salary(uuid, numeric, text) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
