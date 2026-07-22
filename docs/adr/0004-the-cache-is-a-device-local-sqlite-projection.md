# 4. The cache is a device-local SQLite projection, refreshed by delta sync

Date: 2026-07-22

## Status

Accepted. Settles [#7](https://github.com/brzzdev/SimpleYNAB/issues/7). Informed
by the API survey in [#2](https://github.com/brzzdev/SimpleYNAB/issues/2), and
constrained by [ADR-0001](0001-quick-entry-is-a-five-step-flow.md),
[ADR-0002](0002-macos-is-a-menu-bar-only-popover.md) and
[ADR-0003](0003-auth-is-a-pasted-personal-access-token.md).

## Context

ADR-0001 makes quick entry five steps, three of which — payee, account,
category — are populated from the user's YNAB data, and two of which are
*confirmations* of a value already chosen. A confirmation step with nothing in
it is not a degraded step; it is a broken one. So payees, accounts and
categories cannot be fetched on the critical path: they have to be on disk
before the form appears.

The survey in #2 established what the API allows:

- Three delta-capable reads cover everything the form needs — `/accounts`,
  `/payees`, `/categories` — each returning its own `server_knowledge` cursor.
- `GET /plans/{id}` delta-syncs all three in one request, but its *first* call is
  a full plan export including every transaction ever recorded, which is the
  largest response the API produces and carries a documented 30-second timeout.
- 200 requests per hour per token, rolling, with no remaining-quota header since
  v1.73.0. Enough for sync-on-use; not enough for polling.
- **Deletions appear only in delta responses.** A full fetch returns live
  entities only, so a full response merged into an existing cache resurrects
  deleted payees and accounts.

Two platform facts shape when a sync can fire. ADR-0002 makes macOS an
`LSUIElement` that is resident until quit, so "sync on launch" would sync once
and then never again for days; the popover, not the process, is what recurs.
iOS foregrounds far more often. And ADR-0003 already places a network call in
onboarding — a pasted token is verified with `GET /plans` before it is stored —
so onboarding is a moment where the user is already waiting.

The remaining question was how much machinery this justifies. The whole dataset
is small: accounts number in the tens, categories around a hundred, and payees
are the only entity that grows, reaching a few thousand for a long-running
account. At the fields the form needs, that is a few hundred kilobytes.

## Decision

**SQLiteData, in a shared App Group container.** The database lives in an App
Group container on both platforms, with the entitlement added to every target at
scaffold time. This is the move ADR-0003 made for the keychain access group,
repeated for the same reason: the fog ahead includes a Control Center control, a
Lock Screen widget and an App Intent, all of which run in extensions, and
relocating a database is a migration paid at the worst possible moment. App
Groups are same-device only, so this is about extensions, not about the Watch.

**A narrow projection, not a mirror.** Cached rows carry only what the five
steps need:

| Entity | Fields | Notes |
| --- | --- | --- |
| Payee | `id`, `name`, `isTransfer` | `isTransfer` derives from a non-null `transfer_account_id`; transfers are out of scope, so these are excluded from suggestions |
| Account | `id`, `name`, `type`, `closed` | |
| Category | `id`, `name`, `groupID`, `groupName`, `hidden` | YNAB's `internal` categories, such as "Inflow: Ready to Assign", are dropped at write time |
| Plan | `id`, `name`, `currencyFormat` | one row; `decimal_digits` governs minor-unit rendering and milliunit rounding |

No balances, no month amounts, no transactions. The schema is where "SimpleYNAB
is not a YNAB client" stops being a rule someone has to remember: there is no
balance column to accidentally display. `deleted` is not a column either —
tombstones are applied as row deletes, not stored.

**One plan, and the cache records which one.** Rows carry no `planID`. A change
of active plan is a rebuild. Multi-plan remains unspecified; if it later wants
warm switching, adding the column is an additive migration rather than a
redesign.

**Delta sync, one cursor per endpoint.** Each sync sends
`last_knowledge_of_server` to all three endpoints, upserts what returns, deletes
on `deleted: true`, and stores the new cursor. Cursors are never crossed between
endpoints — the survey could not confirm they are comparable. The full plan
export is not used.

**Sync on appearance, throttled, off the critical path.** Every popover open on
macOS and every foreground on iOS kicks a sync, skipped if one ran within the
last five minutes. The form renders from cache first and the sync lands behind
it. No timer, no background refresh task. At three requests per sync, the floor
caps the worst case near 36 requests an hour against a budget of 200.

After a successful `POST`, the `201` body carries the created transaction with
its resolved payee, so a payee created inline by name folds straight into the
cache without waiting for the next delta.

**The first sync belongs to onboarding.** It runs immediately after the token is
verified, as a determinate step, before quick entry is ever shown. This holds an
invariant for the rest of the app's life: **quick entry only appears against a
populated cache**, so none of the five steps needs an empty state.

**No expiry, and staleness is never surfaced.** The cache is valid until
replaced. Since it re-syncs on every appearance, a stale cache implies failing
syncs, which implies offline — and working offline from cache is the feature.
A staleness banner would also have to live on the amount keypad, which ADR-0001
keeps free of chrome.

**One recovery hammer.** Settings offers a single "Refresh now", and it is
always a full rebuild: drop the cursors, delete the rows, refetch all three
endpoints without a cursor, replace wholesale. A delta-only refresh button would
be decoration, because delta already runs automatically; the only reason a
person reaches for refresh is a suspicion the cache is wrong, and only a rebuild
answers that. The same path fires automatically on a failed migration, an
unreadable store, and a change of plan.

**No CloudKit sync of the cache.** SQLiteData ships a `SyncEngine` with
per-table opt-in, and it is deliberately not configured in v1. Every cached row
is a copy of something YNAB owns, so CloudKit would be a second writer with
last-writer-wins and no principled tie-break: a device offline for a week
returns and pushes stale payees over ones the delta has just deleted — the
resurrection hazard, re-entering by another door. Cursors are worse, describing
one device's view: a device inheriting another's cursor asks for changes since a
point its own cache never reached, which is silent drift. It would also grow
sign-out a CloudKit zone teardown that must not race, reopening exactly the
failure ADR-0003 guarded — one YNAB account's data surfacing on a device signed
into another. What it would buy is skipping three requests, once per device,
during onboarding, where the user is already waiting.

The distinction that decides this is *ownership*, not convenience: rows YNAB
owns are never synced; rows only the user owns have no upstream source of truth
and are a legitimate candidate. `SyncEngine`'s per-table opt-in keeps that door
open for preference tables such as hidden accounts and a chosen plan.

## Consequences

- **The cache is disposable and always rebuildable.** Nothing in it is authored
  by the user, so any corruption, drift or doubt is answered by refetching. This
  is why migrations can stay cheap: a migration that cannot be written is
  allowed to fail into a rebuild.
- **A stale cache fails at submit, not before.** A cached account or category
  that YNAB has since deleted is picked in step 3 or 5 and rejected on `POST`.
  No staleness warning would have prevented it, so where that error lands is
  [#16](https://github.com/brzzdev/SimpleYNAB/issues/16)'s question.
- **A missing payee is self-healing.** `payee_name` with a null `payee_id`
  resolves or creates, so a payee added on another device and not yet synced
  costs nothing — the user types it and YNAB matches it by name.
- **Settings inherits a "Refresh now" that is a rebuild**, and gains CloudKit
  sync as an open question for preference tables. Both are inputs to
  [#13](https://github.com/brzzdev/SimpleYNAB/issues/13).
- **Onboarding gains a blocking step**, which
  [#15](https://github.com/brzzdev/SimpleYNAB/issues/15) must order and give a
  failure path — the first sync can fail after a token has been verified.
- **The App Group id pins the reverse-DNS prefix**, alongside the keychain
  access group ADR-0003 pinned. Both are settled at App Store readiness.
- **The Watch is unaffected.** App Groups do not cross devices, so v2's Watch
  does not read this cache; it inherits the token through ADR-0003's shared
  access group and runs the same three-request sync itself. That is cheaper than
  sharing a database and has no conflict semantics to design.
- **The usual category has no source here.** Holding no transactions means the
  cache cannot answer "what category did YNAB last see for this payee", which is
  what makes step 5 a confirmation rather than a decision under ADR-0001. That
  is a real gap this projection creates, not an oversight in it: the answer is
  either an on-demand per-payee fetch between steps 2 and 5, or a locally
  remembered mapping, and it is settled by
  [#17](https://github.com/brzzdev/SimpleYNAB/issues/17).
- **Tests never touch the network.** With no sandbox (per #2), the transport is
  mocked as YNAB's own SDK mocks it, and cursor handling — upsert, tombstone
  delete, rebuild — is tested against fixtures rather than a live plan.
