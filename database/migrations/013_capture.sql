-- ============================================================
-- 013_capture.sql — the photo, and everything that is not typed.
--
-- M5's premise: Esperance's losses come from data that is never captured, and
-- every required field at capture time loses a user. So the primary action in
-- the app is a camera button that writes a row with **zero** required fields
-- beyond the photo itself and the business it belongs to. Details later, or
-- never.
--
-- `documents` already existed (schema.sql, RLS in 004, visibility in 006).
-- What it was missing was everything that makes a capture usable afterwards:
-- a way to retry an upload without creating a second row, the text a phone
-- read off the picture, and a link to the thing the picture turns out to be
-- about.
--
-- Four decisions worth knowing.
--
-- 1. **The row is written after the bytes land, not before.** `r2_key` is not
--    null and never has been. The device uploads to the Worker, gets a key
--    back, and only then records it. A row pointing at an object that does
--    not exist is worse than no row: it puts a broken thumbnail in a gallery
--    and there is nothing the person holding the phone can do about it. The
--    cost is orphaned objects in R2 when the app dies in between, which is a
--    bucket lifecycle rule's problem, not a schema problem.
--
-- 2. **OCR is advisory and never authoritative.** `ocr_text` is stored as the
--    phone read it, and nothing else in this schema reads it. It exists to
--    pre-fill a form that a person then confirms. A misread expiry date that
--    silently became `products.expires_on` would produce exactly the loss
--    this module is meant to prevent, with the app's name on it.
--
-- 3. **A capture belongs to at most one thing, and usually to nothing.**
--    `linked_journal_entry_id` was already there; `product_id` is added
--    beside it. Both null is the normal state and the queue on the home
--    screen is built from it — `unfiled_documents()` is that queue.
--
-- 4. **Idempotency by `client_uuid`, same as everywhere else.** A phone in a
--    market retries. Two rows for one photograph is the retail version of
--    paying the same wage twice.
--
-- Not here: the bytes. No image ever passes through Postgres. See
-- workers/uploads/ for the only thing that may write to the bucket, and why
-- it verifies membership through PostgREST under the caller's own token
-- rather than trusting the org id in the request.
-- ============================================================

-- ------------------------------------------------------------
-- 1. WHAT A CAPTURE CARRIES
-- ------------------------------------------------------------
-- All `if not exists`, all nullable: 013 runs against a live database that
-- already holds documents, and any of these being required would mean the
-- migration has to invent values for rows that were captured before the
-- column existed.

alter table documents add column if not exists client_uuid   uuid;
alter table documents add column if not exists caption       text;
alter table documents add column if not exists content_type  text;
alter table documents add column if not exists byte_size     bigint;
alter table documents add column if not exists captured_at   timestamptz;
alter table documents add column if not exists product_id    uuid;
alter table documents add column if not exists ocr_text      text;
alter table documents add column if not exists ocr_at        timestamptz;
alter table documents add column if not exists barcode       text;
alter table documents add column if not exists device_id     text;

-- Added separately from the column so re-running finds it already there.
-- `on delete set null`: deleting a product must not take the photograph of
-- the delivery it arrived on with it — that picture is the evidence.
do $$
begin
    if not exists (
        select 1 from pg_constraint where conname = 'documents_product_id_fkey'
    ) then
        alter table documents
            add constraint documents_product_id_fkey
            foreign key (product_id) references products(id) on delete set null;
    end if;
end $$;

-- One photograph, however many times the phone sends it. Partial because
-- captures made before 013 have no client_uuid and null is not a duplicate.
create unique index if not exists documents_by_client_uuid
    on documents (org_id, client_uuid) where client_uuid is not null;

-- The gallery, newest first.
create index if not exists documents_by_capture
    on documents (org_id, captured_at desc);

-- The queue: captured and still about nothing.
create index if not exists documents_unfiled
    on documents (org_id, created_at desc)
    where linked_journal_entry_id is null and product_id is null;

-- An object lives at exactly one key, and a second row pointing at the same
-- bytes would double every count on the gallery.
create unique index if not exists documents_by_key on documents (r2_key);

comment on column documents.client_uuid is
    'Client-generated. A retried upload returns the first row rather than making a second.';
comment on column documents.ocr_text is
    'What the phone read off the picture. Advisory: nothing in this schema reads it, a person confirms it.';
comment on column documents.captured_at is
    'When the photograph was taken, which is not when it reached the server. Ignace is offline for days.';

-- ------------------------------------------------------------
-- 2. RECORDING A CAPTURE
-- ------------------------------------------------------------
-- Security definer, like record_entry() and for the same reason: it makes the
-- membership test itself (`can_write_org`, everyone but an observer) so the
-- error is a sentence rather than a policy violation, and it needs auth.uid()
-- which the `authenticated` role cannot reach on its own.
--
-- Every parameter after the key is optional. That is the whole design.
create or replace function record_document(
    p_org_id       uuid,
    p_r2_key       text,
    p_kind         text        default 'photo',
    p_caption      text        default null,
    p_content_type text        default null,
    p_byte_size    bigint      default null,
    p_captured_at  timestamptz default null,
    p_client_uuid  uuid        default null,
    p_device_id    text        default null,
    p_entry_id     uuid        default null,
    p_product_id   uuid        default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor    uuid := auth.uid();
    v_key      text := btrim(coalesce(p_r2_key, ''));
    v_existing uuid;
    v_id       uuid;
begin
    if v_actor is null then
        raise exception 'record_document() needs a signed-in caller';
    end if;

    if not can_write_org(p_org_id) then
        raise exception 'You cannot add documents to this business';
    end if;

    if v_key = '' then
        raise exception 'A document needs the key of the object that was uploaded';
    end if;

    -- The Worker writes under org/<org_id>/…, and only ever for the business
    -- the caller proved membership of. Checking the prefix here as well means
    -- a device cannot record somebody else's object into its own gallery and
    -- read it back through the download route.
    if v_key not like ('org/' || p_org_id::text || '/%') then
        raise exception 'That object does not belong to this business';
    end if;

    if p_client_uuid is not null then
        select id into v_existing
          from documents
         where org_id = p_org_id and client_uuid = p_client_uuid;
        if found then
            return v_existing;
        end if;
    end if;

    -- Same key sent twice without a client_uuid: still one document.
    select id into v_existing from documents where r2_key = v_key;
    if found then
        return v_existing;
    end if;

    if p_product_id is not null and not exists (
        select 1 from products where id = p_product_id and org_id = p_org_id
    ) then
        raise exception 'That product belongs to another business';
    end if;

    if p_entry_id is not null and not exists (
        select 1 from journal_entries where id = p_entry_id and org_id = p_org_id
    ) then
        raise exception 'That entry belongs to another business';
    end if;

    insert into documents (
        org_id, r2_key, kind, caption, content_type, byte_size,
        captured_at, client_uuid, device_id, uploaded_by,
        linked_journal_entry_id, product_id, ocr_status
    )
    values (
        p_org_id, v_key,
        nullif(btrim(coalesce(p_kind, '')), ''),
        nullif(btrim(coalesce(p_caption, '')), ''),
        nullif(btrim(coalesce(p_content_type, '')), ''),
        p_byte_size,
        coalesce(p_captured_at, now()),
        p_client_uuid, p_device_id, v_actor,
        p_entry_id, p_product_id, 'pending'
    )
    returning id into v_id;

    return v_id;
end;
$$;

comment on function record_document(uuid, text, text, text, text, bigint, timestamptz, uuid, text, uuid, uuid) is
    'Records a photograph that has already been uploaded. Every field but the org and the key is optional, on purpose.';

-- ------------------------------------------------------------
-- 3. THE DETAILS THAT ARRIVE LATER
-- ------------------------------------------------------------
-- Filing a capture: giving it a name, or saying what it is about. Split from
-- record_document() because these happen minutes or weeks apart, sometimes on
-- a different phone.
create or replace function file_document(
    p_document_id uuid,
    p_caption     text default null,
    p_kind        text default null,
    p_entry_id    uuid default null,
    p_product_id  uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor  uuid := auth.uid();
    v_org_id uuid;
begin
    if v_actor is null then
        raise exception 'file_document() needs a signed-in caller';
    end if;

    select org_id into v_org_id from documents where id = p_document_id;
    if not found then
        raise exception 'No such document';
    end if;

    if not can_write_org(v_org_id) then
        raise exception 'You cannot change documents in this business';
    end if;

    if p_product_id is not null and not exists (
        select 1 from products where id = p_product_id and org_id = v_org_id
    ) then
        raise exception 'That product belongs to another business';
    end if;

    if p_entry_id is not null and not exists (
        select 1 from journal_entries where id = p_entry_id and org_id = v_org_id
    ) then
        raise exception 'That entry belongs to another business';
    end if;

    -- coalesce, not overwrite-with-null: passing one field must not erase the
    -- other three. Unfiling is a different act and is not offered here.
    update documents
       set caption                 = coalesce(nullif(btrim(coalesce(p_caption, '')), ''), caption),
           kind                    = coalesce(nullif(btrim(coalesce(p_kind, '')), ''), kind),
           linked_journal_entry_id = coalesce(p_entry_id, linked_journal_entry_id),
           product_id              = coalesce(p_product_id, product_id)
     where id = p_document_id;

    return p_document_id;
end;
$$;

-- What the phone read. Kept apart from file_document() so the audit trail can
-- tell a machine's guess from a person's confirmation.
create or replace function set_document_ocr(
    p_document_id uuid,
    p_text        text,
    p_barcode     text default null,
    p_status      text default 'done'
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor  uuid := auth.uid();
    v_org_id uuid;
begin
    if v_actor is null then
        raise exception 'set_document_ocr() needs a signed-in caller';
    end if;

    select org_id into v_org_id from documents where id = p_document_id;
    if not found then
        raise exception 'No such document';
    end if;

    if not can_write_org(v_org_id) then
        raise exception 'You cannot change documents in this business';
    end if;

    if coalesce(p_status, '') not in ('pending', 'done', 'failed', 'skipped') then
        raise exception 'Unknown OCR status: %', p_status;
    end if;

    update documents
       set ocr_text   = nullif(btrim(coalesce(p_text, '')), ''),
           barcode    = coalesce(nullif(btrim(coalesce(p_barcode, '')), ''), barcode),
           ocr_status = p_status,
           ocr_at     = now()
     where id = p_document_id;

    return p_document_id;
end;
$$;

-- ------------------------------------------------------------
-- 4. READING THEM BACK
-- ------------------------------------------------------------
-- Security invoker throughout: these are reads, and the select policy on
-- documents — which since 006 also honours an observer's summary/full
-- visibility — is exactly the rule that should apply. A definer here would
-- hand an observer the line items the 006 policy exists to withhold.

create or replace function org_documents(
    p_org_id uuid,
    p_kind   text default null,
    p_limit  int  default 60,
    p_offset int  default 0
)
returns table (
    id            uuid,
    r2_key        text,
    kind          text,
    caption       text,
    content_type  text,
    byte_size     bigint,
    captured_at   timestamptz,
    ocr_status    text,
    ocr_text      text,
    barcode       text,
    product_id    uuid,
    product_name  text,
    entry_id      uuid,
    entry_label   text,
    uploaded_by   uuid,
    uploaded_name text
)
language sql
stable
security invoker
set search_path = public
as $$
    select d.id, d.r2_key, d.kind, d.caption, d.content_type, d.byte_size,
           coalesce(d.captured_at, d.created_at), d.ocr_status, d.ocr_text,
           d.barcode, d.product_id, p.name, d.linked_journal_entry_id, je.label,
           d.uploaded_by, pr.full_name
    from documents d
    left join products p        on p.id  = d.product_id
    left join journal_entries je on je.id = d.linked_journal_entry_id
    left join profiles pr       on pr.id = d.uploaded_by
    where d.org_id = p_org_id
      and (p_kind is null or d.kind = p_kind)
    order by coalesce(d.captured_at, d.created_at) desc, d.id desc
    limit greatest(coalesce(p_limit, 60), 1)
    offset greatest(coalesce(p_offset, 0), 0);
$$;

-- The pile on the counter. A capture that is about nothing yet is not a
-- mistake — it is the design working — but it is also the only thing in this
-- app that asks a person for a minute of their time, so it needs a number
-- somebody can see going down.
create or replace function unfiled_documents(p_org_id uuid, p_limit int default 60)
returns table (
    id           uuid,
    r2_key       text,
    kind         text,
    content_type text,
    captured_at  timestamptz,
    ocr_status   text,
    ocr_text     text,
    barcode      text
)
language sql
stable
security invoker
set search_path = public
as $$
    select d.id, d.r2_key, d.kind, d.content_type,
           coalesce(d.captured_at, d.created_at), d.ocr_status, d.ocr_text, d.barcode
    from documents d
    where d.org_id = p_org_id
      and d.linked_journal_entry_id is null
      and d.product_id is null
      and coalesce(btrim(d.caption), '') = ''
    order by coalesce(d.captured_at, d.created_at) desc, d.id desc
    limit greatest(coalesce(p_limit, 60), 1);
$$;

-- Scanning something at the counter. Returns the product if this shop already
-- knows the barcode, and nothing if it does not — which is the signal to open
-- the "new product" form with the barcode already in it.
create or replace function product_by_barcode(p_org_id uuid, p_barcode text)
returns table (
    id          uuid,
    name        text,
    sale_price  numeric,
    cost_price  numeric,
    quantity    numeric,
    expires_on  date
)
language sql
stable
security invoker
set search_path = public
as $$
    select p.id, p.name, p.sale_price, p.cost_price, p.quantity, p.expires_on
    from products p
    where p.org_id = p_org_id
      and p.barcode = nullif(btrim(coalesce(p_barcode, '')), '')
    limit 1;
$$;

-- ------------------------------------------------------------
-- 5. RLS
-- ------------------------------------------------------------
-- documents already has select (004, replaced by 006), insert and update
-- policies. Two things 013 needs on top.
--
-- First: the update policy from 004 restricted who may amend a document, but
-- there is still no delete policy anywhere and there deliberately is not one
-- here. A photograph of a delivery is evidence; unfiling it is an update.

-- Second: a document may now point at a product, and a document row must not
-- become a way to learn that another business has a product with a given id.
-- The functions above check it; the policy is what holds when somebody writes
-- to the table directly, which is the whole reason RLS exists.
drop policy if exists "documents point only at their own org" on documents;
create policy "documents point only at their own org"
on documents for update
using (can_write_org(org_id))
with check (
    can_write_org(org_id)
    and (product_id is null or exists (
        select 1 from products p where p.id = product_id and p.org_id = documents.org_id
    ))
    and (linked_journal_entry_id is null or exists (
        select 1 from journal_entries je
        where je.id = linked_journal_entry_id and je.org_id = documents.org_id
    ))
);

-- The 004 update policy is now the weaker of two and would let a direct write
-- past the check above, since Postgres ORs permissive policies together.
drop policy if exists "documents amendable by non-observers" on documents;

-- ------------------------------------------------------------
-- 6. GRANTS
-- ------------------------------------------------------------
-- Every SECURITY DEFINER function starts life executable by PUBLIC, which
-- includes anon. Each refuses a caller with no session already; the revoke
-- makes it deliberate rather than inherited. Same discipline as 005–007.
revoke execute on function record_document(uuid, text, text, text, text, bigint, timestamptz, uuid, text, uuid, uuid) from public;
revoke execute on function file_document(uuid, text, text, uuid, uuid) from public;
revoke execute on function set_document_ocr(uuid, text, text, text) from public;

-- Guarded, the same way 005, 006 and 007 guard theirs: `authenticated` is a
-- Supabase role and does not exist on a bare Postgres, which is what CI
-- starts from. Roles are cluster-wide, so a developer whose cluster has run
-- a test suite before already has it and would never see this fail.
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function record_document(uuid, text, text, text, text, bigint, timestamptz, uuid, text, uuid, uuid) to authenticated;
        grant execute on function file_document(uuid, text, text, uuid, uuid) to authenticated;
        grant execute on function set_document_ocr(uuid, text, text, text) to authenticated;
        grant execute on function org_documents(uuid, text, int, int) to authenticated;
        grant execute on function unfiled_documents(uuid, int) to authenticated;
        grant execute on function product_by_barcode(uuid, text) to authenticated;
    end if;
end $$;

-- PostgREST caches the functions it exposes; without this the app gets
-- "Could not find the function public.record_document in the schema cache"
-- for a minute after the migration lands.
notify pgrst, 'reload schema';
