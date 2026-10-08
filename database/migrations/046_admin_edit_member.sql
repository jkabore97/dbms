-- ============================================================
-- 046_admin_edit_member.sql — an admin edits a member's own information.
--
-- profiles are editable by their owner alone (004): a person fixes the spelling
-- of their own name. The owner asked for the People tab to let an admin see and
-- edit everyone's information. Seeing already works — the profiles select policy
-- lets colleagues read one another — so this adds only the edit, through one
-- SECURITY DEFINER function so no table policy has to be widened.
--
-- Who may edit whom follows the same ladder as a password reset: the function
-- is gated by manages_user() (045), so an admin reaches the staff and the
-- responsables beneath them, a super_admin the admins and below, an owner
-- everyone — and no one a peer or someone above. Body mirrors save_my_profile
-- (017): the same name assembly, the same friendly phone-collision message.
-- ============================================================

create or replace function admin_save_member_profile(
    p_user_id       uuid,
    p_first_name    text,
    p_last_name     text,
    p_middle_name   text default null,
    p_date_of_birth date default null,
    p_title         text default null,
    p_phone         text default null
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_first text := nullif(btrim(coalesce(p_first_name, '')), '');
    v_last  text := nullif(btrim(coalesce(p_last_name, '')), '');
    v_mid   text := nullif(btrim(coalesce(p_middle_name, '')), '');
    v_phone text := nullif(btrim(coalesce(p_phone, '')), '');
    v_full  text;
begin
    if auth.uid() is null then
        raise exception 'admin_save_member_profile() needs a signed-in caller';
    end if;

    -- The whole authorisation, and it is the ladder: a caller may edit only
    -- someone they outrank. manages_user() is false for oneself, so an admin
    -- fixes their own details through the personal form, not here.
    if not manages_user(p_user_id) then
        raise exception 'Vous ne pouvez pas modifier les informations de ce compte.';
    end if;

    if v_first is null or v_last is null then
        raise exception 'Un prénom et un nom de famille sont requis.';
    end if;

    -- full_name stays the one field every screen reads, assembled from the
    -- parts so it never drifts out of step (family name last, as written here).
    v_full := btrim(concat_ws(' ', v_first, v_mid, v_last));

    -- A number already on another account is a mistyped digit far more often
    -- than a real collision; answer in words, not with a constraint name.
    if v_phone is not null and exists (
        select 1 from profiles where phone = v_phone and id <> p_user_id
    ) then
        raise exception 'Ce numéro est déjà utilisé par un autre compte.';
    end if;

    update profiles set
        first_name    = v_first,
        middle_name   = v_mid,
        last_name     = v_last,
        full_name     = v_full,
        date_of_birth = coalesce(p_date_of_birth, date_of_birth),
        title         = coalesce(nullif(btrim(coalesce(p_title, '')), ''), title),
        phone         = coalesce(v_phone, phone)
    where id = p_user_id;
end;
$$;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function admin_save_member_profile(uuid, text, text, text, date, text, text)
            to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
