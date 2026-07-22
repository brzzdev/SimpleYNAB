# YNAB API v1 — what it offers and what it constrains

Research for [#2](https://github.com/brzzdev/SimpleYNAB/issues/2). Answers the ticket's
questions against primary sources only.

**Sources used** (everything below cites one of these):

- **[DOCS]** — <https://api.ynab.com>, the API documentation page. Retrieved 2026-07-22.
- **[SPEC]** — <https://api.ynab.com/papi/open_api_spec.yaml>, the OpenAPI 3.1.1 document,
  `info.version: 1.86.0`. Retrieved 2026-07-22. The rendered endpoint reference at
  <https://api.ynab.com/v1> is generated from this file, so the file is the authority.
- **[SDK-JS]** — <https://github.com/ynab/ynab-sdk-js>, YNAB's official JavaScript client.
  First-party, but generated from [SPEC]; used only where it shows YNAB's own *practice*
  (examples, test strategy, rounding helper).

Anything I could not confirm from those is flagged **[UNCONFIRMED]** rather than guessed.

---

## 0. Read this first: `budgets` is now `plans`

Changelog v1.79.0, 2026-03-05 [DOCS]:

> All API endpoints now use `/plans/{plan_id}` as the primary resource path instead of
> `/budgets/{budget_id}`. Response JSON keys have been updated accordingly: `budgets` is now
> `plans`, `default_budget` is now `default_plan`, and `budget` is now `plan`.
>
> The previous `/budgets/{budget_id}` paths continue to work and will return the original
> response key names for backward compatibility, but are no longer documented.

Every path in [SPEC] 1.86.0 is `/plans/...`; there is no `/budgets/...` path left in the
document. Almost every third-party write-up, and any model I might recall from training,
predates this. **Build against `/plans`.** Note the vocabulary clash with `CONTEXT.md`: YNAB's
UI still says "budget" to users, but its API resource is a *plan*.

Base URL: `https://api.ynab.com/v1` [SPEC `servers`]. The old
`https://api.youneedabudget.com/v1` host still functions but is deprecated [DOCS, Endpoints].

---

## 1. Auth

### The three mechanisms

| Mechanism | Who it is for | Token lifetime | Refresh token | Secret needed |
| --- | --- | --- | --- | --- |
| Personal Access Token | "an individual developer … [accessing] your own account" | "will not expire but can be revoked at any time" | n/a | no |
| OAuth implicit grant (`response_type=token`) | "scenarios where the application Secret cannot be kept private … (i.e. mobile app)" | "expires 2 hours after it was granted" | **no** | no |
| OAuth authorization code grant (`response_type=code`) | "server-side applications, where the application Secret can be protected" | `expires_in: 7200` | **yes** | yes |

All quotes [DOCS, Authentication]. All requests use `Authorization: Bearer <token>`
(RFC 6750) [DOCS, Access Token Usage].

Endpoints:

- Authorize: `https://app.ynab.com/oauth/authorize`
- Token / refresh: `POST https://app.ynab.com/oauth/token`

### PKCE — supported, but *not* as a public-client flow

[DOCS] documents PKCE (RFC 7636) as a security parameter on the authorization code grant:
generate a 43–128 character `code_verifier`, derive `code_challenge` via SHA-256, send
`code_challenge` + `code_challenge_method=S256` on the authorize request and `code_verifier` on
the token request.

**The catch, and it is the load-bearing fact for this app:** YNAB's own documented token-request
example *with* PKCE still sends `client_secret`:

```
curl -X POST https://app.ynab.com/oauth/token \
  -d client_id=[CLIENT_ID] \
  -d client_secret=[CLIENT_SECRET] \
  -d grant_type=authorization_code \
  -d code=[AUTHORIZATION_CODE] \
  -d redirect_uri=[REDIRECT_URI] \
  -d code_verifier=[CODE_VERIFIER]
```

[DOCS, Proof Key for Code Exchange (PKCE)]

In the standard public-client pattern (RFC 8252, what an iOS/macOS app would want) PKCE
*replaces* the secret. YNAB documents it as an *addition* to a confidential-client flow.
**[UNCONFIRMED]**: whether the token endpoint will accept a PKCE exchange with `client_secret`
omitted. Nothing in [DOCS] or [SPEC] says so, and it cannot be tested without a registered
client. Treat "auth code + PKCE with no secret" as unproven until tested against a real client id.

### Redirect URI rules

**[UNCONFIRMED] — and this is a genuine gap, not an oversight in the search.** [DOCS] says only
that the redirect URI is "configured when creating the OAuth Application" and that the
authorize request must pass the same value. Every worked example is an `https://` web URL
(`https://quantumspending.com`). There is **no primary statement anywhere in [DOCS] or [SPEC]
about permitted schemes** — nothing about custom schemes (`simpleynab://`), nothing about
loopback (`http://127.0.0.1:port`), nothing about universal links, no statement of an
https-only rule either. Secondary sources make claims here; none trace back to a YNAB source.

Only the developer settings screen (behind a YNAB login) can settle this. Until someone
registers a test application and tries, this is unknown.

### Other authorize-request parameters [DOCS]

- `scope=read-only` — requests read-only access; a write with such a token gets `403 Forbidden`.
  YNAB asks that you use it if you don't need writes. SimpleYNAB writes, so it cannot.
- `state` — optional but recommended, CSRF protection, echoed back to the redirect URI.
- **Default plan selection** — an optional per-application setting. When enabled the user picks
  a default plan at authorization time, and the app can then pass the literal string `default`
  in place of a `plan_id`, e.g. `/v1/plans/default/accounts`. The literal `last-used` also works
  as a `plan_id` on every plan-scoped endpoint [SPEC, `plan_id` parameter description].

### What registering an OAuth application involves [DOCS]

1. Sign in → Account Settings → Developer Settings → "New Application". You get a Client ID and
   Client Secret.
2. **Restricted Mode.** Every new application starts here: "limited to obtaining 25 access
   tokens for users other than the OAuth application owner". Once hit, new authorizations are
   refused.
3. To lift it you submit a review request form. "This process takes 2-4 weeks."
4. Ongoing obligations, from the OAuth Application Requirements (last updated 2025-05-28):
   - Publish a privacy policy, displayed to users, disclosing what data is collected, how it is
     handled/stored/secured, retention period, a no-onward-transfer guarantee, a user data
     deletion route, and a "Last Updated" date. Display its URL in the OAuth client config.
   - Request minimum necessary permissions.
   - Never request, handle or store financial account credentials.
   - Naming: the app name and DNS name "must not include 'YNAB' or 'You Need A Budget' unless
     preceded by the word 'for'". Acceptable: "Currency Tools for YNAB". Unacceptable: "YNAB
     Tools", "Advanced YNAB". **"SimpleYNAB" is unacceptable under this rule** — it would need
     to be something like "Simple for YNAB".
   - Footer disclaimer of non-affiliation, verbatim text given in [DOCS, API Terms of Service].

### Implication for SimpleYNAB

A shipped App Store app has no safe place for a client secret. That leaves three shapes:

1. **Personal Access Token, pasted by the user.** No registration, no expiry, no refresh, no
   Restricted Mode, no privacy-policy obligation, no naming rule (PATs are not OAuth
   applications). Cost: the user must visit the YNAB web app and paste a token, and [DOCS]
   explicitly frames PATs as "intended to be used only by that same account owner" and "should
   not be shared" — which is satisfied here (each user pastes their own), but note the API
   Terms require that access is granted "through the Authentication processes described in the
   documentation", and that "OAuth is the only option for obtaining access tokens for other
   users". Pasting your own PAT into your own copy of an app is not obtaining someone else's
   token, but this is a judgement call worth an ADR.
2. **OAuth implicit grant.** The flow YNAB explicitly points mobile apps at. Cost: **no refresh
   token, 2-hour expiry.** For a quick-entry app that must be instant on launch, this means a
   full re-authorization web sheet potentially several times a day. That is fatal to the core
   value proposition.
3. **OAuth auth code + PKCE**, either with the secret embedded (unsafe, and the AGPL source
   would publish it) or via a backend that holds the secret (a server SimpleYNAB does not have
   and does not want).

The 2-hour implicit-grant expiry with no refresh is the single hardest auth constraint.

---

## 2. Endpoints

### Reads SimpleYNAB needs

| Purpose | Endpoint | Delta? | Response shape |
| --- | --- | --- | --- |
| List plans (budgets) | `GET /plans` | **no** | `data.plans[]`, plus `data.default_plan` if default plan selection is on. `?include_accounts=true` embeds each plan's accounts. |
| One plan, full export | `GET /plans/{plan_id}` | yes | `data.plan` containing `accounts`, `payees`, `payee_locations`, `category_groups`, `categories`, `months`, `transactions`, `subtransactions`, `scheduled_transactions`, `scheduled_subtransactions` — plus `data.server_knowledge` |
| Accounts | `GET /plans/{plan_id}/accounts` | yes | `data.accounts[]` + `data.server_knowledge` |
| Payees | `GET /plans/{plan_id}/payees` | yes | `data.payees[]` + `data.server_knowledge` |
| Categories | `GET /plans/{plan_id}/categories` | yes | `data.category_groups[]`, each with a nested `categories[]`, + `data.server_knowledge` |

All [SPEC]. Note `/plans` (the *list*) is the one read we need that has **no** delta support —
it is also tiny.

Field notes relevant to v1:

- `Account`: `id`, `name`, `type`, `on_budget`, `closed`, `deleted`, `transfer_payee_id`,
  balances. Filter on `closed` and `deleted` for the account picker. [SPEC `AccountBase`]
- `Payee`: `id`, `name`, `transfer_account_id`, `deleted`. A payee with a non-null
  `transfer_account_id` is the synthetic transfer payee for an account — exclude these from
  payee suggestions, since transfers are out of scope. [SPEC `Payee`, Payees tag description]
- `Category`: `id`, `name`, `category_group_id`, `hidden`, `deleted`, `internal`, plus
  month-scoped amounts. `internal` (added v1.84.0) "indicates if the resource is internally used
  and not user generated" — that is how "Inflow: Ready to Assign" is marked. Categories come
  back *grouped*; the group also carries `hidden`/`deleted`/`internal`. [SPEC `CategoryBase`,
  `CategoryGroup`]
- Category amounts in `GET /categories` "are specific to the current plan month (UTC)" [SPEC].
  Irrelevant to us — we only need names and ids.

### Creating a transaction

`POST /plans/{plan_id}/transactions` [SPEC]

> Creates a single transaction or multiple transactions. If you provide a body containing a
> `transaction` object, a single transaction will be created and if you provide a body
> containing a `transactions` array, multiple transactions will be created. **Scheduled
> transactions (transactions with a future date) cannot be created on this endpoint.**

Responses: `201` on success (`data.transaction_ids` + `data.server_knowledge` +
`data.transaction`/`data.transactions`), `400` on validation error, `409` when "A transaction on
the same account with the same `import_id` already exists."

The `201` body includes the full `TransactionDetail` of what was created, so a transaction that
implicitly created a payee (§6) comes back with the new `payee_id` and `payee_name` — the app can
fold that straight into its payee cache without waiting for the next delta sync. The
`server_knowledge` returned here is the write's own; do not assume it is comparable with the one
from `GET /payees`.

**Required vs optional — read this carefully.** The request body schema is
`SaveTransactionWithOptionalFields`, and **it declares no `required` array at all**; every
property is optional in the schema, including `account_id`, `date` and `amount`. That is true in
the current 1.86.0 spec and was already true in the oldest archived copy I could find
(2024-04-10, via the Wayback Machine). The schema is shared between POST (create) and PATCH
(partial update), which is presumably why.

So the spec does **not** answer "what is required to create a transaction". What primary
evidence exists:

- YNAB's own create-transaction example [SDK-JS `examples/create-transaction/index.mts`] supplies
  `account_id`, `date`, `amount`, `category_id`, `payee_id: null`, `cleared`, `approved`, `memo`.
- The `400 bad_request` error is documented as covering "validation errors" [DOCS, Errors].

**[UNCONFIRMED]**: the exact minimum body. Practically it is `account_id` + `date` + `amount`;
confirm empirically against a live token as part of the first end-to-end call, and pin it with a
test.

Fields (all from [SPEC `SaveTransactionWithOptionalFields` / `NewTransaction`]):

| Field | Type | Notes |
| --- | --- | --- |
| `account_id` | uuid | |
| `date` | ISO date | "Future dates (scheduled transactions) are not permitted." |
| `amount` | int64 | milliunits — see §5 |
| `payee_id` | uuid \| null | |
| `payee_name` | string \| null, max **200** | see §6 |
| `category_id` | uuid \| null | "Credit Card Payment categories are not permitted and will be ignored if supplied." |
| `memo` | string \| null, max 500 | out of scope for v1 |
| `cleared` | `cleared` \| `uncleared` \| `reconciled` | |
| `approved` | bool | **"If not supplied, transaction will be unapproved by default."** A quick-entry app almost certainly wants `approved: true`, otherwise every entry lands in YNAB's approval queue. |
| `flag_color` / `subtransactions` | | out of scope |
| `import_id` | string \| null, max 36 | POST only — see §7 |

---

## 3. Delta sync (`server_knowledge`)

[DOCS, Delta Requests] lists exactly nine delta-capable resources:

```
GET /plans/{plan_id}
GET /plans/{plan_id}/accounts
GET /plans/{plan_id}/categories
GET /plans/{plan_id}/money_movements
GET /plans/{plan_id}/money_movement_groups
GET /plans/{plan_id}/months
GET /plans/{plan_id}/payees
GET /plans/{plan_id}/scheduled_transactions
GET /plans/{plan_id}/transactions
```

Mechanism: the response carries `data.server_knowledge` (int64); pass it back as the
`last_knowledge_of_server` query parameter and "only the data that has changed since the last
request will be included in the response" [DOCS].

### What a delta response omits, and what it *adds*

The delta response is **not** a diff-with-holes of each entity — the worked example in [DOCS]
shows a renamed account returned as a complete `Account` object. What changes is *which*
entities appear: unchanged entities are omitted entirely.

The critical asymmetry, repeated verbatim on `deleted` in every resource schema [SPEC]:

> Whether or not the {account,payee,category,category group,transaction,month,…} has been
> deleted. Deleted {…} will **only be included in delta requests**.

So:

- A **full** (non-delta) fetch returns only live entities. Deletions are invisible.
- A **delta** fetch additionally returns tombstones: the entity with `deleted: true`.

Which means a cache maintained by delta must apply `deleted: true` as a removal, and a cache
rebuilt by full refetch must be replaced wholesale rather than merged — merging a full response
into an existing cache would resurrect deleted rows.

### Practical notes

- **`server_knowledge` values appear to be per-endpoint.** Each delta-capable response returns
  its own value. [DOCS] never says whether a value from `/payees` may be passed to `/accounts`.
  **[UNCONFIRMED]** — so store one `server_knowledge` per endpoint and never cross them.
- `GET /plans/{plan_id}` is a single-request way to delta-sync accounts + payees + categories at
  once, but the *first* call is a full plan export including every transaction ever
  (`getPlanById` takes no `since_date`), which is the largest response the API produces.
  Three targeted calls (`/accounts`, `/payees`, `/categories`) cost 3 requests instead of 1 but
  never download transactions at all. For a quick-entry app that never displays transactions,
  the three-call shape is the better trade despite the extra requests.
- Single-resource endpoints (`GET /categories/{id}` etc.) do **not** support delta;
  `server_knowledge` was removed from their responses in v1.68.1 as a bug fix [DOCS, Changelog].

---

## 4. Rate limits

[DOCS, Rate Limiting], verbatim:

> An access token may be used for up to **200 requests per hour**.
>
> The limit is enforced within a rolling window. If an access token is used at 12:30 PM and for
> 199 more requests up to 12:45 PM and then hits the limit, any additional requests will be
> forbidden until enough time has passed for earlier requests to fall outside of the preceding
> one-hour window.

- **Per access token**, not per application and not per IP. With OAuth each user holds their own
  token, so the budget is effectively per-user-per-installation.
- Rolling one-hour window, not a fixed hourly reset.
- Over the limit: `429 too_many_requests` [DOCS, Errors].
- **No quota header.** Changelog v1.73.0 (2025-01-29): "When a `429 Too Many Requests` response
  is returned because the Rate Limit has been exceeded, a `X-Rate-Limit` response header is no
  longer included." The client cannot see how much budget remains — it can only count its own
  requests or handle the 429.
- Also relevant: `403.4 data_limit_reached` — "The request will exceed one or more data limits in
  place to prevent abuse" [DOCS, Errors]. Undocumented thresholds.
- `503` is documented as covering request timeouts, where "the API request is processing a large
  amount of data and takes longer than 30 seconds to complete" [DOCS, Errors] — another argument
  against the full-plan-export sync shape.

200/hour is generous for launch-sync-and-submit (roughly 4 requests per session) but *not*
generous enough for polling. Sync on launch and after a write; do not poll on a timer.

---

## 5. Milliunits

[DOCS, Data Formats → Numbers]:

> Currency amounts returned from the API—such as account balance, category balance, and
> transaction amounts—use a format we call "milliunits". … 1,000 milliunits equals "one" unit of
> a currency (one Dollar, one Euro, one Pound, etc.).

Their table: `123930` → `$123.93`; `-220` → `-$0.22`; `4924340` → `€4.924,34`; `-2990` →
`-€2,99`; `-395032` → `-395.032` (Jordanian dinar, three decimal places).

### Sign convention for inflow vs outflow

**No primary source states the rule in words.** I searched both [DOCS] and [SPEC] for
"inflow"/"outflow"/"negative"/"positive"; the only hits are the "Inflow: Ready to Assign"
category name. The `amount` field is documented only as "The transaction amount in milliunits
format".

The convention is nevertheless unambiguous from three primary artefacts:

1. [SPEC `NewTransaction.import_id`]: "a transaction dated 2015-12-30 in the amount of **-$294.23
   USD** would have an import_id of `'YNAB:-294230:2015-12-30:1'`" — a spend is negative.
2. [SDK-JS `examples/create-transaction`]: a "Dry Cleaning" purchase is created with
   `amount: -23430`.
3. The [DOCS] milliunits table pairs negative milliunits with negative currency amounts.

**Outflow → negative milliunits. Inflow → positive milliunits.** The UI's inflow/outflow toggle
is nothing more than the sign on `amount`. Confirm on the first live write.

### Rounding

Neither [DOCS] nor [SPEC] states a rounding rule or requires `amount` to be a multiple of ten;
`amount` is just `int64`. But the plan's `currency_format.decimal_digits` [SPEC `CurrencyFormat`]
tells you the currency's precision, and YNAB's own helper rounds to it before converting
[SDK-JS `src/utils.ts`]:

```js
convertMilliUnitsToCurrencyAmount(milliunits, currencyDecimalDigits = 2) {
  let numberToRoundTo = Math.pow(10, 3 - Math.min(3, currencyDecimalDigits));
  numberToRoundTo = 1 / numberToRoundTo;
  let rounded = Math.round(milliunits * numberToRoundTo) / numberToRoundTo;
  …
}
```

i.e. round to the nearest `10^(3 - decimal_digits)` milliunits — nearest 10 for a 2-dp currency
like USD/GBP/EUR, nearest 1 for a 3-dp currency like the Jordanian dinar, nearest 1000 for a
0-dp currency like JPY. Read `decimal_digits` off the plan rather than assuming 2. Do the
decimal→milliunit conversion in integer arithmetic (`Decimal`, or scaled `Int`), never `Double`.

Since v1.82.0 responses also carry `..._formatted` (e.g. `"$1,234.56"`) and `..._currency`
(e.g. `1234.56`) alongside every milliunit field [DOCS, Changelog]. **Requests still take
milliunits only** — there is no `amount_currency` on any Save schema — so the app must still do
the conversion on the way in.

---

## 6. Payees — implicit creation by name

**Yes.** [SPEC `SaveTransactionWithOptionalFields.payee_name`]:

> The payee name. If a `payee_name` value is provided and `payee_id` has a null value, the
> `payee_name` value will be used to resolve the payee by either (1) a matching payee rename
> rule (only if `import_id` is also specified) or (2) a payee with the same name or (3) creation
> of a new payee.

So `payee_id: null` + `payee_name: "Corner Shop"` resolves to an existing payee of that name or
creates one, in a single request. Max length **200** characters on this field.

Rename rules only apply when `import_id` is also set — a good reason *not* to set `import_id`
(see §7), since a rename rule would silently redirect the user's typed payee to a different one.

There is also an explicit `POST /plans/{plan_id}/payees` (added v1.81.0, 2026-03-26), body
`{ "payee": { "name": "…" } }`, `name` required, max length **500**, returning `201` with the
created `Payee` and a `server_knowledge` [SPEC `PostPayee`, `SavePayeeResponse`]. SimpleYNAB does
not need it — implicit creation via `payee_name` is one request instead of two — but note the
inconsistent max lengths (200 on the transaction field, 500 on the payee resource).

---

## 7. `import_id` and retry safety

[SPEC `NewTransaction.import_id`], the whole of it:

> If specified, a new transaction will be assigned this `import_id` and considered "imported".
> We will also attempt to match this imported transaction to an existing "user-entered"
> transaction on the same account, with the same amount, and with a date +/-10 days from the
> imported transaction date.
>
> Transactions imported through File Based Import or Direct Import (not through the API) are
> assigned an import_id in the format: `'YNAB:[milliunit_amount]:[iso_date]:[occurrence]'`. For
> example, a transaction dated 2015-12-30 in the amount of -$294.23 USD would have an import_id
> of `'YNAB:-294230:2015-12-30:1'`. If a second transaction on the same account was imported and
> had the same date and same amount, its import_id would be `'YNAB:-294230:2015-12-30:2'`. Using
> a consistent format will prevent duplicates through Direct Import and File Based Import.
>
> If import_id is omitted or specified as null, the transaction will be treated as a
> "user-entered" transaction. As such, it will be eligible to be matched against transactions
> later being imported (via DI, FBI, or API).

Constraints: max 36 characters; uniqueness is scoped to **(account, import_id)** — the `409`
response on POST is documented as "A transaction on the same account with the same `import_id`
already exists" [SPEC].

### Does it make a retried submit safe?

**Partly, and with a serious side effect.**

What it buys: a retried POST with the same `import_id` cannot create a duplicate. The second
attempt fails with `409 conflict` rather than inserting a second row. So an app that retries an
ambiguous submit (timeout, connection drop) can distinguish "already landed" from "never landed".

What it costs:

1. **It is not idempotent in the usual sense.** The retry returns `409`, not the original `201`
   with the transaction id. The client must treat `409` as success, which is a deliberate
   inversion of the normal reading of that status. (The *bulk* form behaves differently: when a
   `transactions` array is posted, duplicates do not fail the request — they come back in
   `data.duplicate_import_ids`, "a list of import_ids that were not created because of an
   existing `import_id` found on the same account" [SPEC `SaveTransactionsResponse`]. Posting a
   one-element array instead of a `transaction` object is therefore a way to turn the `409` into
   a `201` with an empty result, if that ever reads better.)
2. **It marks the transaction as "imported", not "user-entered".** [SPEC] is explicit that the
   presence of `import_id` is what makes a transaction imported. That changes YNAB-side
   behaviour, including approval and matching semantics.
3. **YNAB will try to merge it into an existing transaction.** "We will also attempt to match
   this imported transaction to an existing 'user-entered' transaction on the same account, with
   the same amount, and with a date +/-10 days." For an app whose entries genuinely *are* the
   user's manual entries, this is a real hazard: buy the same £3.20 coffee twice in a week and
   the second entry can be swallowed by the first. The ±10-day, same-amount, same-account window
   is exactly the shape of everyday repeat spending.
4. **It activates payee rename rules** on `payee_name` resolution (§6), silently changing the
   payee the user typed.

Given that #1 in `CONTEXT.md`'s out-of-scope list is the offline write outbox — v1 surfaces a
failed submit as an error rather than queueing — the retry-safety benefit is small and the
merge hazard is large. **Recommendation: omit `import_id` in v1.** Revisit it only if and when a
background retry outbox lands, and then generate a UUID-derived `import_id` (not the
`YNAB:amount:date:occurrence` format, which is designed to *collide* on repeat amounts).

---

## 8. Sandbox / test mode

**There is none.** Neither [DOCS] nor [SPEC] mentions a sandbox, a test mode, a staging host, or
test credentials. `servers` in [SPEC] lists exactly one entry, `https://api.ynab.com/v1`. The
only "test" facility is the "Test Request" button on the rendered endpoint reference, which
fires real requests against real data with a real token.

### What is done instead — first-party evidence

YNAB's own official JavaScript SDK tests entirely against a **mocked HTTP layer**: `fetch-mock`
intercepting requests to a fake base URL `http://localhost:3000/papi/v1`, with typed response
factories building fixture payloads [SDK-JS `test/requestTests.ts`, `test/factories.ts`]. There
are no live-API integration tests in the repo. Notably, the SDK's `API` constructor takes a base
URL as its second argument specifically to permit this.

That is the pattern to copy, and it maps cleanly onto the map's TDD-with-Swift-Testing
constraint:

- Unit/domain tests: fixtures captured from the real API once, replayed through a stubbed
  transport; `@Dependency`-injected client so nothing touches the network.
- End-to-end proof (the map's "one real YNAB API call proven end to end"): a scratch YNAB plan
  and a Personal Access Token, run manually, never in CI. A YNAB trial account is finite —
  `403.2 trial_expired` is a documented error [DOCS] — so a live scratch budget has an expiry
  date attached to it.

---

## 9. The short list of things that constrain the design

1. **`/plans`, not `/budgets`** (v1.79.0). Everything written before March 2026 is wrong here.
2. **OAuth implicit grant = 2-hour tokens with no refresh.** It is the flow YNAB points mobile
   apps at, and it is incompatible with "instant on launch". Auth-code+PKCE-without-a-secret is
   **[UNCONFIRMED]** and may not exist. Personal Access Tokens never expire and need no
   registration — for a single-user quick-entry tool that is the only mechanism that fits the
   product without a backend.
3. **Redirect URI scheme rules are undocumented.** If OAuth is on the table at all, registering a
   throwaway application and testing `simpleynab://` and loopback URIs is a prerequisite, not a
   detail.
4. **200 requests/hour per token, rolling, no remaining-quota header.** Sync on launch and after
   a write. Never poll.
5. **Delta sync is the whole caching story**: three `last_knowledge_of_server` calls
   (accounts, payees, categories) refresh the form's data for 3 requests, and after the first
   sync usually return almost nothing. Store one `server_knowledge` per endpoint.
6. **Deletions only appear in delta responses.** A cache merged from a full refetch will
   resurrect deleted payees and accounts. Full refetch must replace, not merge.
7. **`payee_name` with `payee_id: null` creates the payee.** No pre-flight payee creation call,
   so "type a payee YNAB has never seen" is one request.
8. **Outflow is negative milliunits**, inferred (soundly) rather than stated. Round to the plan's
   `currency_format.decimal_digits`; requests take milliunits only.
9. **`approved` defaults to `false`.** Send `approved: true` or every quick entry lands in the
   user's approval queue.
10. **Skip `import_id` in v1.** It marks entries as "imported" and lets YNAB merge them into
    same-amount transactions within ±10 days — a live hazard for repeat spending, bought in
    exchange for a retry guarantee v1 does not use.
11. **No sandbox.** Mock the transport (as YNAB's own SDK does) and keep one manual live test
    against a scratch plan.
12. **Non-technical, but binding:** the OAuth Application Requirements forbid an app name
    containing "YNAB" unless preceded by "for". If SimpleYNAB ever ships as an OAuth
    application, the name has to change.
