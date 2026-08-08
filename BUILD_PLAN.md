# Kaj App — Build Plan

Every task below is written to be pasted directly into Claude Code, in order.
Each milestone ends with something demonstrable.

---

## Where things stand

**Done and tested**

| Piece | Status |
|---|---|
| orgs → entities → departments | schema built |
| 8 scoped roles (owner…employee, observer, approver) | built |
| Double-entry ledger, hidden behind plain-language actions | built, tested |
| Offline outbox + idempotent sync | built, tested |
| Undo by reversal (append-only history) | built, tested |
| 22 RLS policies, cross-tenant isolation | built, proven by test |
| Church contributions + expenses | built |
| Pastor's weekly summary, member giving statements | SQL built, no screen |
| Flutter app running on web and Android | built |

**Not built**

Login. Org switching. Admin screens. Farm module. Store module. Photos and OCR.
Invoices. Report screens. Custom domains. Employee/payroll. The `orgId` in
`main.dart` is hardcoded, which is why only one church appears.

---

## M1 — Login and org resolution

The single highest-value change: it turns a one-church demo into a
multi-tenant product.

> Build authentication and org resolution.
>
> 1. Add a login screen: phone number + OTP as the primary method (most users
>    have no email), with email/password as a secondary option. Use Supabase
>    auth.
> 2. After sign-in, query the user's memberships. If they belong to exactly
>    one org, go straight to its home screen. If several, show a picker.
>    If none, show a "waiting for invitation" screen.
> 3. Delete the hardcoded orgId and orgName from main.dart. Everything must
>    come from the signed-in user's memberships.
> 4. Store the session so it survives weeks offline — Ignace has no signal.
>    Add a device PIN for re-entry when the token cannot be refreshed.
> 5. Route to the right home screen based on the org's `profile` column
>    ('church' | 'farm' | 'retail').
>
> Test on web with a real Supabase user before saying it works.

**Demo after M1:** two different people log in and see different businesses.

---

## M2 — Admin screens

> Build the admin section, visible only to owner/super_admin/admin roles.
>
> - Org settings: name, currency, profile.
> - Entities: create/edit/list (farm sites, church campuses, store branches).
> - Departments within entities.
> - People: list members, invite by phone or email, assign a role at a chosen
>   scope (org / entity / department), set observer visibility to full or
>   summary, revoke access.
> - Invitations via a short code or QR so a temp employee can join by scanning
>   Esperance's phone. No email required.
>
> Enforce with the existing RLS — an admin of one org must not touch another.

**Demo after M2:** you create a business, add staff, and hand out access without
touching SQL.

---

## M3 — Reports and the accountability loop

Israel's pastor and Ignace's investors are the reason the data gets entered
carefully. Make them visible.

> Build report screens over the existing SQL functions.
>
> - Weekly summary (church_weekly_summary) with a share-as-image/PDF button
>   for WhatsApp — likely the most-used feature in the app.
> - Cash balances (church_balances).
> - Member giving statements (member_giving_statement) for year-end.
> - Observer view: honour `visibility` — 'summary' sees totals only, 'full'
>   sees line items.
> - A "Close the day" button on the home screen: shows money in, money out,
>   what is pending, and a streak counter.

**Demo after M3:** the pastor gets a Sunday summary on WhatsApp automatically.

---

## M4 — Ignace's farm

> Add the farm profile module, following the patterns in
> 002_church_profile.sql.
>
> Schema (005_farm_profile.sql):
> - items (feed, medicine, supplies) with units and reorder thresholds
> - stock_movements (received, consumed, wasted) — append-only, like the ledger
> - flocks: batch id, bird count, arrival date, breed
> - flock_events: mortality, weight samples, vaccination
> - egg_production: date, flock, count, grade
> - customers and invoices with payment tracking
>
> Every write goes through a function that also writes the matching ledger
> entry — feed purchased is both a stock movement and an expense. Follow the
> record_contribution pattern exactly: plain-language inputs, accounting hidden,
> client_uuid for idempotency.
>
> Screens: home with today's feed/eggs/mortality, stock in/out, flock detail,
> egg sales, invoice creation and sharing.
>
> Add tests to database/tests/ proving the ledger stays balanced.

**Demo after M4:** Ignace records a feed delivery with no signal; his investor
sees the summary the next time either device syncs.

---

## M5 — Esperance's store

The hardest and highest-value module. Her losses come from data never captured.

> Add the retail profile module.
>
> Capture-first design: the home screen's primary action is a large camera
> button that creates a record with ZERO required fields. Photo now, details
> later or never. Every required field at capture time loses a user.
>
> - Photo upload to Cloudflare R2 (bucket `kaj-app-uploads` already exists),
>   path recorded in the existing `documents` table.
> - On-device OCR with Google ML Kit (free, works offline) to read product
>   name, serial number, expiry date, price from the photo. User confirms
>   with one tap rather than typing.
> - Barcode scanning for known products.
> - products: name, serial, barcode, expiry, cost, price, quantity, photos
> - sales and returns, tied to the ledger
> - employees: permanent and temporary, shifts, salary/wage, payments
> - Expiry alerts: "3 items expiring in 14 days — 82 000 at risk"
> - A running "losses avoided" total. This is the number that renews her
>   subscription.

**Demo after M5:** she photographs a delivery invoice and the products are in
the system without typing.

---

## M6 — Domains and distribution

> - Deploy workers/tenant-router to Cloudflare and populate the
>   `kaj-tenant-routing` KV namespace (id 87160dd3344245959ab7ca4532cfe169)
>   with hostname → org mappings.
> - Wildcard DNS so every tenant gets `{slug}.kajapp.com`.
> - Cloudflare for SaaS for custom domains (`app.theirbusiness.com`).
> - Email domain claim: TXT record verification, then anyone with that email
>   domain auto-joins the org.
> - Play Store release: upload keystore, signed release build, store listing.

---

## Sequencing

M1 first — without it there is no multi-tenant product.
M3 before M4: reports are what make people enter data carefully, and they cost
little once the SQL exists.
M4 and M5 can run in parallel if you bring in another developer.

## What matters more than any of this

Get M1 done, then put the app in Israel's hands and watch him use it. One real
user for a week will reorder this list more usefully than any amount of
planning.
