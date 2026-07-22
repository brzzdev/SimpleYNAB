# Context: SimpleYNAB

SimpleYNAB is a quick-entry front end for [YNAB](https://api.ynab.com). Its
whole job is: launch, type an amount, pick a payee, done. It is **not** a YNAB
client — it does not show plans, balances, or existing transactions.

This glossary grows lazily, as decisions actually settle terms. Use these words
in code, issues and tests; don't drift to the synonyms noted below.

## Glossary

**Plan** — what YNAB used to call a budget. As of API v1.79.0 (2026-03-05) the
resource is `/plans/{plan_id}` and the JSON keys are `plans`, `plan`,
`default_plan`. **Never say "budget"** except when quoting YNAB's own user-facing
UI. Anything written before March 2026 is stale on this point. Settled by
[#2](https://github.com/brzzdev/SimpleYNAB/issues/2).

**Quick entry** — the five-step flow that is the entire app: amount → payee →
account → date → category. Every step is confirmed, including the ones already
correct. Settled by [ADR-0001](docs/adr/0001-quick-entry-is-a-five-step-flow.md).

**Step** — one screen of quick entry, holding exactly one decision. Steps are
numbered and always run in the same order; there is no skipping and no jumping
to save.

**Draft** — the transaction being entered, from the first keystroke until it is
saved or abandoned. A draft is never persisted; abandoning one loses it.

**Minor units** — how an amount is typed. Digits fill from the right, so `1234`
is £12.34 and a decimal point is never entered. This is the input *model*; iOS
renders it as a keypad, macOS drives it from the number row.

**Milliunits** — how an amount is sent. YNAB's wire format, three decimal
places, with outflow **negative**. `−12340` is an outflow of £12.34. Convert at
the API boundary; never let milliunits leak into the UI layer.

**Usual category** — the category YNAB last saw on a transaction for a given
payee. Quick entry pre-fills step 5 from it, which is what makes that step a
confirmation rather than a decision.

**Inflow / outflow** — the direction of a transaction, chosen in step 1. Outflow
is the default and is sent as a negative milliunit amount.

**Personal access token** — the only credential SimpleYNAB holds. The user
generates it on YNAB's web app and pastes it in; it never expires and is never
refreshed. Say "token", not "API key" or "login". Settled by
[ADR-0003](docs/adr/0003-auth-is-a-pasted-personal-access-token.md).

**Invalid token** — the state a token enters when YNAB answers `401`, meaning it
was revoked. The token stays in the keychain and the app offers to **reconnect**;
it is never deleted automatically, because the item syncs and a false positive
would sign every device out at once.

**Cache** — the local SQLite projection of one plan's payees, accounts and
categories, holding only the fields the five steps need. It is device-local,
never synced between devices, and always disposable — every row is a copy of
something YNAB owns, so it can be thrown away and refetched. It holds no
balances and no transactions. Settled by
[ADR-0004](docs/adr/0004-the-cache-is-a-device-local-sqlite-projection.md).

**Sync** — one pass of the three delta reads that refresh the cache. Fires on
popover open or foreground, throttled, and never on the critical path: the form
is drawn from the cache before a sync is even requested. Say "sync", not
"fetch" or "refresh", for this.

**Cursor** — a stored `server_knowledge` value, one per endpoint, marking how
much of that endpoint the cache has seen. Cursors are per-device and are never
crossed between endpoints.

**Rebuild** — dropping the cursors, deleting every row and refetching from
scratch. The only manual refresh the app offers, and the automatic answer to a
failed migration, an unreadable store, or a change of plan. A rebuild is always
total; there is no partial one.

**Populated-cache invariant** — quick entry only ever appears against a
populated cache. The first sync happens during onboarding, so no step ever needs
an empty state.

**Sign out** — the deliberate teardown of everything the YNAB account produced:
the token, the cache, every `server_knowledge` cursor, and account-derived
preferences. It is always global, because deleting a synchronizable keychain item
deletes it on every device. Device state — launch at login, the answered
first-run prompt — is **not** account data and survives.
