# Project rules — read this before starting any work

These exist because each one was learned by actually getting it wrong once
in this project. Follow them without being asked again.

## Before opening a PR

- Rebase onto current `main` first, always — not just when it seems relevant.
  A branch merged without this once silently reverted a CI fix that had
  already landed.
- Check the highest migration number across *every open branch*, not just
  main, before naming a new one. Two branches have independently claimed the
  same migration number before.
- If the task includes a small documentation or cleanup step alongside a
  larger feature (updating BUILD_PLAN.md, deleting a superseded branch,
  putting something on its own branch), do the small step *in the same PR*,
  not as a mental follow-up. Small steps bundled with large ones have been
  silently dropped, repeatedly, in favor of finishing the large one.

## Before saying something is done

- Run it and look at the actual output. A successful `flutter build` is not
  the same as a page that renders — a real regression shipped that way once.
- If a task specifies "own branch, open a PR" for one piece of work, don't
  fold it into a different branch already in progress, even if it's related.

## Scope

- If building the requested thing surfaces a real bug (a security issue, a
  broken assumption), fix it and say so clearly — don't stay silent about
  scope growing.
- But don't expand a milestone into the next one without being asked, even
  if it's obviously coming next. A "reports and history" task once grew to
  include an entire unrelated module three milestones ahead of schedule.
  Flag it, offer to split, wait for confirmation before merging that part.

## Standing technical facts, not to be rediscovered

- Ship targets are web and Android only. Never add macos/windows/linux/ios
  scaffolding — `flutter create` generates it by default; delete it.
- Supabase credentials reach the app only via `--dart-define`, sourced from
  Codespaces secrets. Never hardcoded, never committed, never pasted into
  chat by anyone, including you.
- `record_contribution`, `record_expense`, and similar are SECURITY INVOKER
  on purpose — they're bound by the same RLS as a direct table write.
  `create_org` is SECURITY DEFINER on purpose — RLS cannot gate an insert
  into a table whose row doesn't exist yet to check membership against.
  Don't "fix" either direction without understanding which is which.
- A Postgres view runs as its owner, bypassing RLS, unless created with
  `security_invoker = on`. Every view added to this schema needs that
  explicitly — one view shipped without it and quietly leaked every org's
  data to anyone holding the public key.
- Since 063 a new function is born closed to `anon` and `PUBLIC`
  (default privileges), and every SECURITY DEFINER function outside the
  street is revoked from `anon`. A function the signed-out storefront
  must call needs an explicit `grant execute … to anon`. A function an
  RLS policy calls must stay executable by every role the policy applies
  to — the policy runs it as the caller — and `test_least_privilege.sql`
  pins the six that are.
