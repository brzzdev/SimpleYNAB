# 5. Modules are a SwiftPM package behind a thin Tuist app shell

Date: 2026-07-23

## Status

Accepted. Settles [#9](https://github.com/brzzdev/SimpleYNAB/issues/9). Informed
by the Tuist survey in [#3](https://github.com/brzzdev/SimpleYNAB/issues/3), and
constrained by [ADR-0001](0001-quick-entry-is-a-five-step-flow.md),
[ADR-0002](0002-macos-is-a-menu-bar-only-popover.md),
[ADR-0003](0003-auth-is-a-pasted-personal-access-token.md) and
[ADR-0004](0004-the-cache-is-a-device-local-sqlite-projection.md).

Refines #3's *expression* findings — external dependencies, the settings block
and `PackageSettings` move as described below — without contradicting its
higher-level calls (one generated project, `Derived/` gitignored, the
`acronyms`/`bundleId` fix), which still hold.

## Context

The prior ADRs already imposed the seams: a credential layer nothing else may
assume the shape of (ADR-0003), a cache that is a device-local projection
(ADR-0004), an AppKit shell confined to the macOS status item (ADR-0002), and a
five-step flow identical on both platforms (ADR-0001). What #9 settles is the
module graph those seams live in, and how it is expressed under Tuist.

The #3 survey verified a *pure-Tuist* expression: modules as
`ProjectDescription.Target`s in one `Project.swift`, the strict regime applied
once at `Project(settings:)`, external packages via `.external(name:)`. It also
surfaced a wrinkle — Xcode 26.6 has no build-setting key for
`ImmutableWeakCaptures`, so that one upcoming feature needs `OTHER_SWIFT_FLAGS`.

A second expression exists and is already running in the author's SimpleScrobble
— a near-identical app on the same stack (TCA, `swift-dependencies`, SQLiteData,
macOS 26, an `LSUIElement` menu-bar app, a keychain client seam, per-feature
modules). There, the modules are library targets in a root `Package.swift`, and
Tuist generates only a thin `.app` target over an `AppHost/` that depends on the
package. That split is the decision below.

## Decision

### Pattern: a SwiftPM package of modules, wrapped by a thin Tuist app shell

**The modules are SwiftPM library targets in a root `Package.swift`.** The Tuist
`Project.swift` declares only the two thin app targets (iOS and macOS), each
depending on the package's product and holding what SwiftPM cannot express for a
real `.app`: signing, entitlements (the keychain access group and App Group from
ADR-0003/0004), `Info.plist` (`LSUIElement`), build-phase lint scripts, schemes
and test plans.

The two expressions produce the *same* module graph; only the declaration site
differs. This one is chosen over pure-Tuist for three reasons that are not mere
consistency with SimpleScrobble:

1. **The `ImmutableWeakCaptures` wrinkle stops touching module code.** The
   modules compile through SwiftPM, where `.enableUpcomingFeature("Immutable­Weak­Captures")`
   is a first-class setting. The `OTHER_SWIFT_FLAGS` workaround from #3 survives
   only on the two Xcode-compiled app targets.
2. **The logic modules are `swift test`-able with no Tuist or Xcode boot** — the
   fast inner loop a TDD-leaning project wants.
3. **Dependency direction is enforced by SwiftPM itself.** A target cannot import
   a module it did not declare — it is a compile error, not a lint — and the
   whole DAG is legible in one `Package.swift`. This is a stronger guarantee than
   the `tuist inspect dependencies` check pure-Tuist would have relied on, and it
   is what makes the "`Credentials` never imports `YNABClient`" rule below
   structural rather than aspirational.

### The module graph

Five library modules and two app targets:

```
  App (iOS target)      App (macOS target)      ← Tuist; scene + AppKit shell + wiring
            \                  /
             \                /
                  Feature                        ← TCA reducers + shared SwiftUI step views
              /     |      \
          Cache  Credentials  YNABClient
            |    (leaf)     /     |
            |              /      |
            └────► YNABDomain ◄───┘               ← pure value types
```

- **`YNABDomain`** — the shared value types (`Payee`, `Account`, `Category`,
  `Plan`, the minor-unit `Amount`, currency format). Near dependency-free.
  Persistence-agnostic: the SQLiteData `@Table` projection types live in `Cache`,
  not here, so the domain owes nothing to the store.
- **`Credentials`** — owns the token seam and the `Credential` type. A leaf
  depending only on `SharingKeychain` and `Dependencies`. It does **not** import
  `YNABClient` (see the seam below).
- **`YNABClient`** — the YNAB transport. Depends on `Credentials` (for the bearer
  token) and `YNABDomain` (for the types it decodes into).
- **`Cache`** — the SQLiteData projection *and* the delta-sync engine, as one
  module (ADR-0004). Depends on `YNABClient` and `YNABDomain`. An internal seam
  is kept between *reading* the projection and *syncing* it, so a v2 App-Group
  reader (Control Center, widget, App Intent — ADR-0004's fog) can be promoted to
  its own module without a rewrite; it is not split now.
- **`Feature`** — the composed `AppReducer`, its sub-reducers (quick entry,
  onboarding, settings) and the shared SwiftUI step views. **SwiftUI only — no
  `UIKit`, no `AppKit`.**
- **Two app targets** (Tuist) — the composition root and platform chrome. The
  macOS `NSStatusItem`/`NSPopover`/`NSHostingController` shell lives here and
  nowhere else (ADR-0002's "AppKit confined to the shell"); iOS has its
  `App`/`WindowGroup`. Each injects live dependencies and hosts the shared root
  view in its own container.

Reducers are shared wholesale — ADR-0001 makes the flow identical, so iOS and
macOS diverge only in presentation. The one genuinely forked view, amount input
(iOS keypad vs macOS number row, ADR-0001), is handled *inside* `Feature` with
plain SwiftUI, not pushed up into the app targets — which is also what keeps
`Feature` buildable for watchOS.

### The credential seam

ADR-0003 requires that nothing outside the credential layer assume the token was
pasted, never expires, or came from the keychain, because the App Store release
is expected to switch to OAuth-with-refresh. The seam that satisfies it:

- **Persisted and synced:** `@Shared(.keychain("token", accessGroup: …,
  accessibility: .whenUnlocked, synchronizable: true)) var token: String?` via
  `SharingKeychain`. `nil` means absent/signed-out. This is the storage-and-UI
  surface — onboarding, Settings and the reconnect affordance all bind to it.
- **Invalidity is in-memory**, per ADR-0003 ("marks the credential invalid *in
  memory*"): a separate `isInvalid` flag that `report401()` sets, never written
  to the synced keychain item — so a transient 401 on one device does not flip
  every device.
- **The feature sees a derived enum**, which is where illegal states become
  unrepresentable (`token == nil` dominates, so there is no "absent but
  invalid"):

  ```swift
  enum Credential { case none; case token(String); case invalid(String) }

  var credential: Credential {
    guard let token else { return .none }
    return isInvalid ? .invalid(token) : .token(token)
  }
  ```

- **The client sees only two functions**, never the shared value:
  `token() async throws -> String` (v1 reads the `@Shared`; v2 refreshes
  transparently — an `async` call is what lets refresh hide, which a value read
  could not) and `report401()`. `YNABClient` depends on this interface and
  nothing more.
- **Paste-verification keeps `Credentials` a leaf.** ADR-0003 wants `GET /plans`
  before a token is stored, but that call belongs to `YNABClient`. Onboarding
  verifies by overriding the token dependency with the candidate for one call,
  then storing on success — so no bad token reaches the keychain and
  `Credentials` never imports `YNABClient`:

  ```swift
  try await withDependencies { $0.credentials.token = { candidate } }
    operation: { try await ynab.getPlans() }   // 200 ⇒ credentials.store(candidate)
  ```

`SharingKeychain` (`brzzdev`, MIT) supplies exactly ADR-0003's storage trio —
`accessGroup`, `accessibility: .whenUnlocked` (= `kSecAttrAccessibleWhenUnlocked`),
`synchronizable: true` — plus an in-memory `KeychainClient` test value. It must
be made public (or vendored) to ship as a dependency of an open-source app; that
is [#18](https://github.com/brzzdev/SimpleYNAB/issues/18).

### The strict regime, applied at two sites

Because the modules compile through SwiftPM and the app targets through Xcode,
the regime is applied twice — same rules, two drivers:

- **Modules:** the `for target in package.targets { … }` loop at the foot of
  `Package.swift` — the exact block from the map Notes — enabling the six
  upcoming features (`ImmutableWeakCaptures` included, natively) and
  `treatAllWarnings(as: .error)` on every target.
- **App targets:** the Tuist settings apply `SWIFT_STRICT_CONCURRENCY = complete`,
  the five `SWIFT_UPCOMING_FEATURE_*` keys, `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`
  and `OTHER_SWIFT_FLAGS` for `ImmutableWeakCaptures`. **The app shell is not
  exempt** — the macOS AppKit code is held to the same strictness as everything
  else.

`PackageSettings` is left clean; the #3 survey reproduced three build failures
from pushing our flags onto external package targets. Dependencies keep their
authors' regime.

### watchOS

The v2 Watch app runs the same flow, so every library module carries the
constraint; only the app targets are platform-bound. It is honored by rule now
and verified in v2:

- **The package declares `iOS 26` and `macOS 26` only.** `.appleWatch` is not
  added now — the runtime is not installed on the build machine, so adding it
  breaks the local build for no v1 gain, and "watchOS actually compiling" is
  already parked in the map's fog.
- **No shared module imports `UIKit` or `AppKit`** — `YNABDomain`, `Credentials`,
  `YNABClient` and `Cache` are Foundation-only; `Feature` is SwiftUI-only. AppKit
  lives solely in the macOS app target.
- **A lint enforces it**, since watchOS cannot compile-check it here: CI fails if
  any file under the package's `Sources/` imports `UIKit` or `AppKit`. That is
  the guard that keeps watchOS open between now and v2; otherwise a stray import
  compiles clean on iOS and surfaces only when someone installs the runtime.

### Test targets

**One SwiftPM `.testTarget` per logic module** — `YNABDomainTests`,
`YNABClientTests`, `CacheTests`, `CredentialsTests`, `FeatureTests` — each
exercising its module through its interface, `swift test`-able, Swift Testing
throughout (no XCTest). They inject the seams: `YNABClient` a mock transport (no
sandbox, per #2), `Credentials` `SharingKeychain`'s in-memory `KeychainClient`,
`Cache` a fake client for delta-merge fixtures, `Feature` TCA's `TestStore`. The
app targets get no test target.

**Plus one `FeatureSnapshotTests`** over the shared step views, using
`swift-snapshot-testing` as a test-only dependency, multiplatform with per-`#if
os()` sizing to pin both the macOS popover (ADR-0002) and the iOS full-screen
presentation, reference images committed. Unlike the logic tests it renders per
platform, so it runs through the Tuist scheme / `xcodebuild` (iOS simulator +
macOS), not bare `swift test`. Kept separate from `FeatureTests` so image diffs
and slower renders stay out of the fast logic loop.

## Consequences

- **The Tuist layer shrinks to what only Xcode can do.** Signing, entitlements,
  `Info.plist`, schemes, test plans and lint phases — the module graph and its
  language regime leave `Project.swift` entirely. This is the split
  [#10](https://github.com/brzzdev/SimpleYNAB/issues/10) scaffolds.
- **`Credentials` importing `YNABClient` is now a compile error, not a
  convention.** The one-directional token seam ADR-0003 asked for is enforced by
  the package graph.
- **`SharingKeychain` must go public.** A private dependency cannot be resolved
  by an open-source checkout, so [#18](https://github.com/brzzdev/SimpleYNAB/issues/18)
  blocks the scaffold. It is MIT and `brzzdev`-owned, so it flows into AGPL with
  no CLA question (per `CLAUDE.md`).
- **The regime lives in two files.** A change to the strict settings must be made
  in both the `Package.swift` loop and the Tuist app-target settings, because the
  two compile through different drivers. The lint and warnings-as-error catch
  drift, but the duplication is real and deliberate — it is the cost of not
  exempting the app shell.
- **Manifests are now two, and both meet SwiftFormat.** `Package.swift` joins
  `Project.swift` as a formatted, staged Swift file; the `acronyms`/`bundleId`
  fix from #3 (`--preserve-acronyms bundleId`, or SimpleScrobble's
  `// swiftformat:disable acronyms`) is [#12](https://github.com/brzzdev/SimpleYNAB/issues/12)'s
  to settle, now across both.
- **Snapshot tests are the one suite that needs the simulator.** CI cannot run
  the whole test story with `swift test` alone; the snapshot target pulls in
  `xcodebuild`, which [#10](https://github.com/brzzdev/SimpleYNAB/issues/10)'s CI
  wiring must account for.
- **Granularity was collapsed deliberately.** SimpleScrobble runs ~16 modules
  (each client and feature its own); SimpleYNAB has one external client and one
  real feature, so the fine split would be ceremony. If `Feature` later grows
  sub-features worth isolating, splitting a SwiftPM target out is additive.
- **watchOS rests on a lint, not a build.** Until the runtime is installed and
  `.appleWatch` added (v2), "no shared module imports UIKit/AppKit" is only as
  true as the lint makes it. The lint is therefore load-bearing, not hygiene.
