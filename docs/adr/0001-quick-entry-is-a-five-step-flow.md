# 1. Quick entry is a five-step flow

Date: 2026-07-22

## Status

Accepted. Settles [#4](https://github.com/brzzdev/SimpleYNAB/issues/4).

## Context

SimpleYNAB's whole claim is "instant": launch, type an amount, pick a payee,
done. A transaction needs six things — amount, payee, account, date, category,
inflow/outflow direction — and the design question was how to get all six
without any of them costing anything.

Four structurally different forms were built and used on both surfaces (branch
[`prototype/quick-entry-form`](https://github.com/brzzdev/SimpleYNAB/tree/prototype/quick-entry-form)):

- **A — Form.** All six fields visible at once; speed from defaults and tab order.
- **B — One thing at a time.** Amount → payee → confirm, with account, date and
  category pre-filled and shown only on the confirm screen.
- **C — One line.** `12.34 tesco @amex #groceries yesterday`, parsed live.
- **D — Payee first.** Pick from a grid of recents, then a keypad.

Each was instrumented with a live interaction counter, so "minimum number of
interactions from launch to saved" was measured rather than argued about.

B won. A puts six targets on screen and makes you aim at each one. C is fast
once learned but has to be learned, and is poor under a thumb. D's inversion is
appealing but the payee grid is a wall of choices at the moment you have the
least patience for one.

## Decision

**Quick entry is a five-step flow.** One decision per screen, in this order:

1. **Amount**, with the inflow/outflow control **above** the amount.
2. **Payee**. Suggestions appear **only once you type** — no recents, no list
   before the first keystroke.
3. **Account**, defaulting to the last used.
4. **Date**, defaulting to today.
5. **Category**, defaulting to the category last used for the payee chosen in
   step 2.

**Every step is confirmed, including the ones that are already right.** There is
no skip, no jump-to-save, no shortcut past steps 3–5. Five steps, five confirms,
one way to finish — the flow is identical every time, so it becomes muscle
memory. The cost is knowingly accepted: three confirmations of values the user
did not choose.

**On save, confirm and get out.** A brief success state (~0.7s) showing what was
saved, then the macOS popover closes itself. iOS cannot quit, so it shows the
same success state and returns to step 1.

**Amount is entered in minor units.** Digits fill from the right — `1234` is
£12.34 — and a decimal point is never typed. This is the *model*; the input
surface differs by platform. iOS renders a keypad. macOS drives the same model
from the number row, because a grid of mouse targets is strictly slower than
typing and, in a 340×460 popover, leaves room for nothing else.

## Consequences

- **The interaction floor is five**, and no amount of good defaulting lowers it.
  If the flow ever feels slow, this is the decision to reopen — not the
  defaults.
- **Steps 3–5 must be one-tap targets.** Their whole justification is that
  confirming is trivial; a picker that needs scrolling or aiming breaks the
  bargain.
- **The payee → category default is load-bearing.** Step 5 is only a
  confirmation if it is usually correct. If YNAB's payee history turns out to be
  a poor predictor, step 5 becomes a real decision and the flow gets slower.
- **Dismissing on save means a failed write cannot be shown in place.** The
  window is gone before the user can react. Error handling has to survive that —
  see the error-states work still on the map.
- **Account filtering becomes necessary.** Step 3 lists accounts you would never
  post to from a phone, and every one of them is noise in a step that has to be
  trivial. This creates the need for a Settings surface.
- **macOS needs a typing affordance.** Observed during the prototype: with no
  keypad on screen, it is not obvious the amount can be typed until you try it.
  The number-row path needs to advertise itself.
- **Rejected: an escape hatch.** A "save now" from step 3 onward would cut the
  common case to three actions, and was rejected deliberately — two ways to
  finish makes the flow conditional, and a flow you have to think about is not
  muscle memory.
