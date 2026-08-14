# Kaj App — Build Plan

Every task below is written to be pasted directly into Claude Code, in order.
Each milestone ends with something demonstrable.

---

## Where things stand

**Done and tested**

| Piece | Status |
|---|---|
| orgs → entities → departments | schema built |
| Invitations by short code, no email required (M2) | built, tested — 585-line suite |
| Platform admin flag + create_org (006) | built, tested — no screen yet |
| Admin screens: org settings, entities/departments, people, invites | built (M2) |
| Expense entry alongside contributions | built |
| Public web build on Cloudflare, redeploys on push to main | live |
| Codespace serve.sh — local dev serving with real credentials | built |
| 8 scoped roles (owner…employee, observer, approver) | built |
| Double-entry ledger, hidden behind plain-language actions | built, tested |
| Offline outbox + idempotent sync | built, tested |
| Undo by reversal (append-only history) | built, tested |
| 22 RLS policies, cross-tenant isolation | built, proven by test |
| Church contributions + expenses | built |
| Flutter app running on web and Android | built |
| Login by email/password, org resolution, profile routing (M1) | built, tested offline |
| Offline session + device PIN | built, tested |
| Admin screens: people, roles, structure, settings (M2) | built |
| Invitations by short code or QR | built, 15 assertions |
| Report screens: weekly summary, balances, giving, close-the-day (M3) | built |
| Visibility ('summary' vs 'full') actually enforced | built, proven by test |
| Account creation — sign up by phone or email, then join with a code | built, tested |
| Free-text entry names, notes and characteristics | built, tested |
| Accounting: journal, résultat, bilan, grand livre, balance | built, 16 assertions |
| Editable chart of accounts, transfers between cash accounts | built |
| Activity log + super admin console (logs, data, device) | built, 10 assertions |
| Ignace's farm: stock, flocks, eggs, invoices (M4) | built, 17 assertions |
| Esperance's store: products, sales, returns, expiry alerts (M5) | built, 11 assertions |
| Employees, shifts and payroll (M5) | built, 8 assertions |
| Camera capture with zero required fields, R2 upload (M5) | built, 10 assertions |
| Barcode scanning and on-device OCR (M5) | built, 22 assertions, unproven on a device |
| A photographed delivery note becoming stock (M5) | built, 17 + 5 assertions |
| Serial numbers and a product's photographs (M5) | built, 2 assertions |
| Renaming, archiving and deleting a business | built, 25 assertions |
| Employee sign-up: profile, then a code from their manager | built, 17 assertions |
| Manager sign-up: apply, be approved, own the business | built, in the same suite |
| Staff records for every business, volunteers included | built, 17 assertions |
| A farm with livestock and crops, not only poultry | built, 11 assertions |
| Invoicing for every business, not only the farm — numbered, cancellable, shareable as an image | built, 14 assertions |
| Phone numbers with a country code picker, stored as E.164 | built, 12 assertions |
| A colour per business profile, measured against WCAG rather than eyeballed | built, 14 assertions |
| Platform console: search, filter and page across thousands of businesses | built, 8 assertions |

**Not built**

Custom domains. Reading an invitation QR with the camera — today the invitee
types the code, though the scanner built for barcodes is now most of what
that needs. Attributing a contribution
to a named church member from the recording sheet (the SQL and the giving
statement both support it; the sheet has no member picker yet). An invoice
leaves as a rendered image, which is what WhatsApp actually wants — a true PDF
export is still not built.

**Not yet verified**

None of the network paths has been exercised against a real Supabase project:
no credentials. Specifically unproven end to end —

- The SMS round trip. Phone sign-in needs an SMS provider enabled under
  Authentication → Providers → Phone.
- Email sign-up, which behaves differently depending on whether "Confirm email"
  is on. The app handles both (`response.session == null` means the account
  exists and nobody is signed in yet), but only one of the two has ever run.
- `SyncService` posting `record_entry`, `record_transfer`, `receive_stock`,
  `move_stock`, `record_flock_event` and `record_eggs`. The payload keys are
  asserted against the SQL signatures in `app/test/record_entry_test.dart` and
  `app/test/farm_offline_test.dart`, which is the failure this would otherwise
  produce on somebody's phone days later, but no request has actually been
  made.

Also unproven: the upload Worker. `workers/uploads/` has never had a real
photograph put through it, because it needs a deployed Worker with an R2
binding and a live Supabase token. Its authorisation is delegated entirely to
RLS, which *is* tested — `database/tests/test_capture.sql` is one shop
reaching for another's pictures — but the HTTP path itself has not run.

Everything below the network — routing, org resolution, the offline path, the
ledger, the policies, the reports, the log, the farm's two ledgers, the shop's
counter, the payroll and the capture queue — is covered by 147 Flutter tests
and fifteen SQL suites (178 assertions).

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

## M3.5 — Accounts, names, books and a console

Three gaps that only became visible once M1–M3 were on screen together.

**1. There was no way to get an account.** The only route in was an invitation
from somebody who already had the app, and the only way to be first was for
Kaj-consulting to run an INSERT. Sign-up now sits beside sign-in on the login
screen, and signing in with an unknown number is refused rather than silently
creating a second account for a mistyped digit. The order this teaches is
deliberate: make the account, then join the business with a code. An account on
its own grants nothing.

**2. Entries could not be named.** Four kinds of contribution and seven expense
categories, all compiled into the app and into 002. Anything real that was not
on that list got filed under whichever category was least wrong. That was
defended as protecting the books from seven spellings of "Loyer", but a
category list nobody can add to does not produce clean books — it produces
books where "Fournitures" means eleven things and no report can separate them.

> `record_entry()` takes the words the person typed. `ensure_account()` turns a
> name into an account the first time and finds the same one every time after,
> matching case-insensitively and on trimmed text, because that is how a name
> arrives from a phone keyboard. The chips are now the accounts the books
> already hold — so choosing one posts the exact stored name and cannot open a
> duplicate — and "Autre…" is a text field. Each entry also carries a note and
> any number of typed characteristics as jsonb.

**3. The ledger had been double-entry the whole time and nothing could show it
as one.** Journal, income statement, balance sheet, general ledger with a
running balance, trial balance, an editable chart of accounts, and transfers
between cash accounts — without which banking the Sunday offering is recorded
as earning it twice.

**4. Nothing recorded who changed what.** The ledger was always its own audit
trail, which covers money; every decision about *who may touch* the money was
silently mutable. An admin could grant themselves ownership, act, and revoke it
with no trace anywhere. `008_audit_log.sql` adds one append-only table, one
generic trigger, and RLS with a select policy and no insert, update or delete
policy at all — the only writer is the trigger, which runs outside policy, so
the owner of a business cannot erase their own history. Most of
`test_audit.sql` is them trying.

The console that reads it has three tabs because three different questions get
asked in the same five minutes: what happened (the log), what is actually
stored (every table, its purpose, this org's row count, its columns and
foreign keys), and what this phone is still holding — which finally reads
`outbox.last_error` and tells "waiting for signal" apart from "the server
refused this".

**Demo after M3.5:** somebody signs themselves up, joins with a code, records
"Réparation du toit" with the mason's name attached, and the owner opens the
income statement and sees it — then opens the log and sees who recorded it.

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

**Built.** `009_farm_profile.sql` (the plan numbered it 005; that slot went to
invitations while the farm waited). Two departures from the text above, both
deliberate:

- **Feed is expensed when bought, not when eaten.** The plan says "feed
  purchased is both a stock movement and an expense" and that is what was
  built. The strictly correct treatment capitalises it as inventory and
  expenses it on consumption, which would smooth the income statement and give
  the stock account a value. It is not done, because it matches how the money
  actually feels to the person paying for it — the day twenty sacks arrive is
  the day the money is gone — and because a real inventory valuation is a
  conversation with an accountant rather than something to guess at. Noted at
  the top of the migration.
- **Two writes need the server.** Opening a flock and raising an invoice are
  not offline-first, unlike the four things Ignace does every day. A batch code
  and an invoice number both have to be unique across the business, and two
  disconnected phones inventing the same one would split a cycle's figures in
  half with nothing to say so. Everything he does standing in a poultry house
  works with no signal; the two things he does sitting down do not.

The suite tests the four specific ways this module inflates profit: feed
expensed twice, eggs booked as income before anyone pays, an invoice earned
once when raised and again when settled, and a dead bird expensed on top of
the feed it already ate.

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

**Partly built.** `011_retail_profile.sql` and the store screens: products
with prices, counts and expiry dates, sales and returns posting through the
same `record_entry()` every other module uses, expiry alerts valued in money,
and a losses-avoided total. Selling is idempotent by `client_uuid`, so the
phone can retry.

Employees, shifts and payroll are built — `012_employees.sql`, and the
Personnel screen behind the store's home screen.

The capture half is built too — `013_capture.sql`, `workers/uploads/`, and the
camera button that is now the store's primary action. It takes a photograph
with zero required fields, keeps the bytes on the device until there is
signal, and files them in R2 under `org/<org_id>/…` through a Worker that
authorises by forwarding the caller's own token to PostgREST. Naming a picture
or attaching it to a product is a separate act, done later or never.

Two departures from the text above, both deliberate:

- **The upload is a Worker, not a pre-signed URL.** Pre-signing still needs a
  server to decide who may have a URL, and once that server exists the signing
  buys nothing but a second moving part that holds a key.
- **The photograph is recorded after the bytes land, never before.** A row
  pointing at an object that does not exist puts a broken thumbnail in a
  gallery with nothing the person holding the phone can do about it. The cost
  is orphaned objects when the app dies in between, which is a bucket
  lifecycle rule's problem rather than a schema's.

**Complete**, including the demo — *she photographs a delivery invoice and the
products are in the system without typing.*

`InvoiceReading` turns a photographed delivery note into lines, and the
confirm screen turns those into stock and a purchase in the books with one
button. Nothing is written before that button. **Arithmetic is what makes it
safe**: a line is `Savon 12 500`, which is either twelve at five hundred or
one at twelve thousand five hundred, and no amount of staring at it settles
that — but a line carrying a total does, because only one reading multiplies
out. Both tokenisations are tried and the checked one wins; where neither
checks, the French reading is used and the line is marked as unverified so it
is the one a person looks at.

Building it caught a real defect in 011, fixed in `016_stock_receipts.sql`:
`receive_products()` passed its `client_uuid` to the ledger and still added to
`products.quantity` unconditionally. A retried delivery counted the goods
twice and the money once, so the shelf and the books disagreed by exactly one
delivery with nothing on any screen to say so. It also closes something 011
claimed and did not do — its header says the quantity column can be rebuilt
from history, which was true of sales and never of deliveries, because stock
arriving was recorded nowhere. `stock_receipts` is what makes that sentence
true.

`015_product_serial.sql` adds the `serial` the plan's product list asks for —
011 built `sku` and called it close enough, which it is not: a SKU names a
kind of thing, a serial identifies one phone — and `product_photos()`, which
reads `documents.product_id` back the other way round so the "photos" in that
same list are reachable from the product.

The two accelerators: barcode scanning at the counter, and on-device OCR.

Scanning finds a product by its code in one tap through `product_by_barcode()`
and, when the shop has never seen the code, says so rather than inventing a
product from a number. It works on both ship targets.

OCR is Android only and reached through a conditional import, so the web build
compiles a stub and never resolves ML Kit. It reads the photograph on the
device: no connection needed, and no picture of anybody's invoice leaves the
phone to be read. What it reads is offered as suggestions and **applied to
nothing** — the rule stated in `013_capture.sql` and asserted from both sides,
because a misread expiry date that silently became `products.expires_on` is
the exact loss this module exists to prevent, with the app's name on it. The
parser errs toward offering nothing: an ambiguous label leaves the box empty,
which costs one person ten seconds instead of costing a shop money for as long
as nobody notices.

**Not verified, and cannot be here:** no Android SDK exists in the environment
this was built in, so the APK has not been compiled and neither the scanner
nor the reader has run on a device. The web build is verified — built, served
and rendered — and the parser has 22 assertions over it, but the plugins
themselves are unproven until somebody installs it on a phone.

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

M1 through M5 are built. What is left is M6 — domains and distribution — and
it is the wrong thing to do next. A week with one real user will reorder the
rest of this list more usefully than any amount of planning, and none of it
has been in anybody's hands yet.

## What matters more than any of this

Put the app in Israel's and Ignace's hands and watch them use it. Everything
through M5 is tested against Postgres and against a fake device; almost none of
it has been tested against a person.

One real user for a week will reorder this list more usefully than any amount
of planning. The first thing that week will produce is a list of category and
item names nobody predicted, which is now something the app absorbs rather than
something that has to be shipped — and the second will be a number somebody
reads differently than it was meant. M6 is what is left, and it is
distribution: doing it before anybody has used the thing distributes a guess.
