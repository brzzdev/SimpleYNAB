# 2. macOS is a menu-bar-only popover, built on AppKit

Date: 2026-07-22

## Status

Accepted. Settles [#5](https://github.com/brzzdev/SimpleYNAB/issues/5). Builds on
[ADR-0001](0001-quick-entry-is-a-five-step-flow.md).

## Context

ADR-0001 fixed what the form does. This decides what surrounds it on macOS: how
the app is invoked, what kind of window the form lives in, and what the app's
identity is on the system.

Two facts about the macOS 26.5 SDK, checked against
`SwiftUI.swiftinterface` rather than recalled, shaped the whole decision:

- **`MenuBarExtra` cannot be opened in code.** Its only binding is `isInserted`,
  which controls whether the *icon* is present, not whether its window is shown.
- **`MenuBarExtra` cannot be closed in code either.** `DismissWindowAction`
  addresses scenes by `id`, and `MenuBarExtra` is not one. The third-party
  `MenuBarExtraAccess` package exists precisely to paper over this.

The second fact is disqualifying on its own. ADR-0001 requires the window to
close itself roughly 0.7s after a save — "confirm and get out" is the payoff the
five-step bargain was sold on — and SwiftUI offers no supported way to do it.

## Decision

**The app is an `LSUIElement` accessory app.** No Dock icon, no ⌘-Tab entry, no
app-switcher presence. It is resident until explicitly quit; having no windows,
there is nothing to quit for.

**The status item is an `NSStatusItem`,** created in an
`NSApplicationDelegateAdaptor`. Left-click toggles the popover. Right- or
control-click opens a small `NSMenu` holding **Settings…** and **Quit**. The five
flow screens carry no chrome whatsoever.

**The window is an `NSPopover`** with `behavior = .transient`, anchored to the
status button via `showRelativeTo`. The form inside is SwiftUI hosted in an
`NSHostingController`, so nearly all the code remains SwiftUI; AppKit is confined
to the shell.

**Invocation for v1 is the status item click.** No global hotkey.

**On focus loss the popover dismisses, and the in-flight entry survives for ~5
minutes.** Reopen inside that window and you resume mid-flow; reopen after it and
you start clean at step 1. The entry is never written to disk, so a relaunch is
always fresh.

**Launch at login is `SMAppService.mainApp.register()`,** behind a Settings
toggle that defaults to off, with one explicit ask during first run.

**The sandbox needs `com.apple.security.network.client` and nothing else.**
`NSStatusItem`, `NSPopover` and `SMAppService.mainApp` all work unprivileged, and
none conflict with App Store distribution.

## Consequences

- **A v2 global hotkey is an addition, not a rewrite.** `showRelativeTo` can be
  called from anywhere. Had `MenuBarExtra` been chosen for its brevity, the
  hotkey would have meant replacing the status item, the window and the
  positioning together.
- **`TextEditingCommands` must be declared.** With no app menu there is no Edit
  menu, and on macOS the Edit menu is what dispatches ⌘V. First-run auth is
  *paste a personal access token*, so an app that skips this line has a token
  field you cannot paste into.
- **The resume horizon exists to defeat muscle memory.** ADR-0001 optimises for
  thumbs that move without reading, so a resumed day-old entry would confirm and
  post itself. A summary line would not save you, because muscle memory is
  exactly the mode that ignores one. Five minutes is a tuning knob; the existence
  of a horizon is not.
- **Onboarding becomes load-bearing,** carrying three jobs: accepting the token,
  asking about launch at login, and teaching the right-click menu, which is
  otherwise undiscoverable.
- **The error path has nowhere to land.** ADR-0001 noted that a self-closing
  window cannot report a failed write. `LSUIElement` narrows the escape routes to
  three: change the status item icon, post a user notification, or reopen the
  popover. There is no Dock icon to badge and nothing to bounce.
- **AppKit is a permanent dependency of the macOS target,** which the module
  layout has to accommodate — the shell cannot live in a shared module that must
  also build for watchOS.
- **Rejected: `MenuBarExtra` plus an AppKit dismiss hack.** Poking at
  `NSApp.keyWindow` or calling `NSApp.hide(nil)` would close a window SwiftUI
  owns, through undocumented behaviour, inside a Swift 6 strict-concurrency
  codebase. It works until an OS update decides otherwise, and then it fails
  silently.
