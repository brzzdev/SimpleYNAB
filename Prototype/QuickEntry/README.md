# Quick-entry form prototype — THROWAWAY

Four structurally different quick-entry forms, switchable from a floating bar,
running as a macOS menu-bar popover and an iOS app off one set of views.

Answers [#4 — Quick-entry form: what "instant" actually looks like](https://github.com/brzzdev/SimpleYNAB/issues/4).

**This code is throwaway.** No tests, no error handling, no TCA, no networking —
all fake data, all in memory. It decides nothing about the real project layout;
the crude Tuist manifest exists only so the same views can run on both platforms
before the real scaffold ([#10](https://github.com/brzzdev/SimpleYNAB/issues/10))
lands. Nothing here is promoted as-is.

## Run it

```sh
just prototype-mac              # menu bar → click the £ icon
just prototype-ios              # boots the simulator and launches
just prototype-ios "iPhone 17"  # a different simulator
```

## The four variants

Cycle with the arrows in the floating bar, or ⌘[ / ⌘] on macOS. The choice
sticks across launches. Switching resets the draft, so the interaction count is
always per-variant.

| | Variant | The structural claim |
|---|---|---|
| **A** | Form | Everything visible at once, nothing is a step. Six fields, so show six fields; speed comes from defaults and tab order. |
| **B** | One thing at a time | Amount → payee → confirm. A form is slow because it makes you aim; a wizard never does. Account/date/category get no step, only a confirm-screen row. |
| **C** | One line | `12.34 tesco @amex #groceries yesterday`. Nothing beats never leaving the keyboard — at the cost of having to be learned, and of being poor under a thumb. |
| **D** | Payee first | You know *who* before *how much*, and the payee is what fixes the category. One tap on a recents tile, then a keypad that is the only thing on screen. |

## What to watch while you flip

The eye button opens a state readout: resolved fields, YNAB milliunits, and a
live **interaction count**. Every discrete action — keystroke, tap, menu pick —
bumps it, so the ticket's "minimum number of interactions from launch to a saved
transaction" gets measured rather than guessed. The green banner on save reports
the count and elapsed seconds for that transaction.

Two entry models are in play, which is the keypad-vs-decimal-field question:

- **A and C** use a plain decimal field — you type `12.34` yourself.
- **B and D** use minor units — digits fill from the right, so `1234` is £12.34
  and no decimal point is ever typed. On iOS that renders as a keypad; on macOS
  the same model is driven from the number row, so the comparison holds on both.

Payees carry a `usualCategory`, and picking one pre-fills the category. Whether
that is reliable enough to hide the category field entirely is the thing to
judge — it is why B and D can get away with showing so little.

## Known rough edges (deliberate)

- The macOS popover opens on a menu-bar click, not a global hotkey. The real app
  would bind a hotkey; the layout question doesn't depend on it.
- Payee matching is prefix → contains → subsequence. That is *not* the payee
  matching decision (still fog on the map), just enough to judge the UI.
- C's grammar is deliberately dumb. The question is whether typing a line
  **feels** right, not whether the grammar is any good.
- Nothing dismisses itself on save yet — the banner stays so the count is
  readable. What "done" looks like is one of the things to decide.
