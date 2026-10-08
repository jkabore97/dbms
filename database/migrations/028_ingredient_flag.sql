-- ============================================================
-- 028_ingredient_flag.sql — what is cooked with, not sold.
--
-- The flour question, settled. A shop that transforms — cakes, soap, shea
-- butter — holds two kinds of product on the same shelf: things it sells
-- and things it only cooks with. The tables and the accounting treat them
-- identically on purpose (an ingredient is an ordinary product received at
-- its real price), but the *screens* should not: at two hundred articles,
-- the sale picker offering flour at 0 F is an accident waiting for a
-- thumb, and the production picker burying ten real ingredients under a
-- hundred and ninety finished goods is a scroll nobody should do twice.
--
-- One boolean, no rules attached. `is_ingredient` is a signpost for the
-- pickers — the sale sheet hides flagged products, the production sheet
-- surfaces them first. It is deliberately NOT enforced server-side:
-- record_sale() still accepts an ingredient, because the shop that bakes
-- with flour on Monday and sells the surplus sack on Friday is not an
-- edge case here, it is the neighbourhood. Staff can flip the flag the
-- same way they edit a price.
-- ============================================================

alter table products
    add column if not exists is_ingredient boolean not null default false;

comment on column products.is_ingredient is
    'A signpost for the pickers: hidden from the sale sheet, surfaced first in production. Not a rule — selling one is still allowed.';

notify pgrst, 'reload schema';
