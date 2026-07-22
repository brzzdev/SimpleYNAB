# Tuist project layout for SimpleYNAB

Research for [#3](https://github.com/brzzdev/SimpleYNAB/issues/3) (map: [#1](https://github.com/brzzdev/SimpleYNAB/issues/1)).

**Verified against:** Tuist 4.202.6 (Homebrew cask), Xcode 26.6 (17F113), Swift 6.3.3
(swiftlang-6.3.3.1.3), macOS 26 (Darwin 25.5.0), on 2026-07-22. Every manifest snippet below was
actually generated and built in a throwaway project; where something was only read and not run, it
says so.

Dependency versions resolved during verification: swift-composable-architecture 1.26.1,
swift-dependencies 1.14.1, sqlite-data 1.7.0 (pulling GRDB 7.11.1, swift-syntax 603.0.2,
swift-collections 1.6.0, swift-sharing 2.9.1, swift-structured-queries 0.33.3 and friends).

---

## TL;DR — the decisions this forces

1. **One `Project.swift`, no `Workspace.swift`.** Tuist synthesises the workspace containing our
   project plus one generated project per external package. Verified: `tuist generate` produced
   `SimpleYNAB.xcworkspace` from a `Project.swift` alone.
2. **The `for target in package.targets { … }` block becomes a `SettingsDictionary` in
   `Tuist/ProjectDescriptionHelpers`, applied once at `Project(settings:)`.** Target-level
   repetition is unnecessary.
3. **Five of the six upcoming features have a `SWIFT_UPCOMING_FEATURE_*` build setting in Xcode
   26.6. `ImmutableWeakCaptures` does not** and needs `OTHER_SWIFT_FLAGS`. Verified by grepping
   Xcode's `Swift.xcspec`.
4. **`PackageSettings` *can* push those flags onto external package targets — and doing so breaks
   the build.** Three separate, reproduced failure modes (§4). Leave `PackageSettings` alone.
5. **One multi-platform target per shared framework**, not one per destination. Adding watchOS later
   is a two-line change and external package `SUPPORTED_PLATFORMS` follows automatically (§5).
6. **SwiftFormat's `acronyms` rule rewrites `bundleId:` to `bundleID:` in `Project.swift` and Tuist
   then refuses to generate.** Reproduced end to end. Fix: `--preserve-acronyms bundleId` (§7).
7. **Swift Testing needs nothing declared** beyond `product: .unitTests` — no package dependency, no
   test plan (§8).

---

## 1. Manifest shape

### What Tuist expects on disk

The `Tuist/` directory marks the project root; the working directory must hold either
`Project.swift` or `Workspace.swift`
([directory structure](https://tuist.dev/en/docs/guides/features/projects/directory-structure)):

| File | Role (Tuist's words) |
| --- | --- |
| `Tuist.swift` | "configuration for Tuist that's shared across all the projects, workspaces, and environments" |
| `Project.swift` | "define the targets that are part of the project, and their dependencies" |
| `Workspace.swift` | "group other projects and can also add additional files and schemes" |
| `Tuist/Package.swift` | "Swift Package dependencies for Tuist to integrate them using Xcode projects and targets" |
| `Tuist/ProjectDescriptionHelpers/` | "Swift code that's shared across all the manifest files" |

### Project vs Workspace

Tuist's [manifests page](https://tuist.dev/en/docs/guides/features/projects/manifests) says a
`Workspace.swift` "customizes the workspace that Tuist generates. By default, Tuist creates a
workspace containing the project and its dependencies' projects automatically." Its stated reason
for the multi-project split — avoiding `.xcodeproj` merge conflicts — does not apply, because the
generated project is never committed. It recommends a single project for faster cold generation.

**Verified.** With only `Project.swift` present, `tuist generate` emitted:

```
Generating workspace SimpleYNAB.xcworkspace
Generating project SimpleYNAB
Generating project swift-composable-architecture
Generating project sqlite-data
… (one per transitive package)
Total time taken: 0.987s
```

and `xcodebuild -list` on that workspace showed only *our* schemes
(`SimpleYNAB-iOS`, `SimpleYNAB-macOS`, `SimpleYNABKit`, `SimpleYNAB-Workspace`) — the external
package projects are in the workspace but do not pollute the scheme list.

**Recommendation:** a single `Project.swift` at the repo root. Revisit only if the target count
makes cold generation slow, which at four targets it is not (~1.2 s).

### `Tuist.swift`

```swift
import ProjectDescription

let tuist = Tuist(
	project: .tuist(
		compatibleXcodeVersions: .upToNextMajor("26.0")
	)
)
```

Two traps, both hit during verification:

- **`compatibleXcodeVersions: "26.0 ..< 27.0"` silently means "exactly 26.0.0".**
  `CompatibleXcodeVersions` is `ExpressibleByStringInterpolation` and its `init(stringLiteral:)` is
  `self = .exact(Version(stringLiteral: value))`
  ([source](https://github.com/tuist/tuist/blob/4.202.6/cli/Sources/ProjectDescription/CompatibleXcodeVersions.swift)).
  Generation failed with *"The selected Xcode version is 26.6, which is not compatible with this
  project's Xcode version requirement of 26.0.0."* Use `.upToNextMajor(_:)`.
- **`generationOptions: .options(enforceExplicitDependencies: true)` is deprecated.** The overload
  carries `@available(*, deprecated, message: "enforceExplicitDependencies is deprecated. Use
  'tuist inspect dependencies --only implicit' instead.")`
  ([source](https://github.com/tuist/tuist/blob/4.202.6/cli/Sources/ProjectDescription/ConfigGenerationOptions.swift)).
  Put `tuist inspect dependencies` in CI instead — see §7.

---

## 2. External dependencies

Declared in `Tuist/Package.swift`, resolved by `tuist install`, linked with `.external(name:)`
([dependencies guide](https://tuist.dev/en/docs/guides/features/projects/dependencies)).

**Verified `Tuist/Package.swift`:**

```swift
// swift-tools-version: 6.1
import PackageDescription

#if TUIST
import ProjectDescription

let packageSettings = PackageSettings(
	baseProductType: .staticFramework
)
#endif

let package = Package(
	name: "SimpleYNABDependencies",
	dependencies: [
		.package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.7.0"),
		.package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.26.1"),
		.package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.14.1"),
	]
)
```

Notes:

- `.staticFramework` is already `PackageSettings`' default `baseProductType`
  ([source](https://github.com/tuist/tuist/blob/4.202.6/cli/Sources/ProjectDescription/PackageSettings.swift));
  spelling it out is documentation, not behaviour. Override per product via
  `productTypes: ["Foo": .framework]` if a package misbehaves when static.
- **No `products:` or `targets:` array is needed** — only `dependencies:`. Tuist reads the graph and
  generates one Xcode project per package.
- **SQLiteData's package traits resolved without complaint.** sqlite-data 1.7.0 declares SwiftPM
  traits (`CasePaths`, `Tagged`, `LazyInitializableByDefault`); `tuist install` and `tuist generate`
  both succeeded with the default trait set. *Not verified:* enabling a non-default trait through
  Tuist.
- Macro packages work. Tuist builds the macro executables and injects
  `-load-plugin-executable …#ComposableArchitectureMacros` (etc.) into `OTHER_SWIFT_FLAGS`
  automatically; `@Reducer` and `@ObservableState` compiled.

**Linking, verified:**

```swift
dependencies: [
	.external(name: "ComposableArchitecture"),
	.external(name: "Dependencies"),
	.external(name: "SQLiteData"),
]
```

`swift-dependencies` is a transitive dependency of TCA, but listing it explicitly is correct: Tuist
ships `tuist inspect dependencies`, which fails on implicit dependencies (a target importing a
module it doesn't declare). Verified — it caught exactly that in the test target:

```
The following implicit dependencies were found:
 - SimpleYNABKitTests implicitly depends on: ComposableArchitecture
```

---

## 3. Swift settings and upcoming features — where the Notes' block goes

### There is no `.enableUpcomingFeature` in ProjectDescription

`SettingsTransformers.swift` — the file holding every `SettingsDictionary` convenience — has
helpers for code signing, versioning, `swiftVersion(_:)`, `otherSwiftFlags(_:)`,
`swiftCompilationMode(_:)` and so on, **and nothing for upcoming features**
([source](https://github.com/tuist/tuist/blob/4.202.6/cli/Sources/ProjectDescription/SettingsTransformers.swift)).
Settings are raw Xcode build settings: `SettingsDictionary = [String: SettingValue]`
([source](https://github.com/tuist/tuist/blob/4.202.6/cli/Sources/ProjectDescription/Settings.swift)).

### Which of the six features Xcode 26.6 knows about

Grepping Xcode's Swift build-settings spec:

```
/Applications/Xcode.app/Contents/SharedFrameworks/SwiftBuild.framework/Versions/A/PlugIns/
  SWBBuildService.bundle/Contents/PlugIns/SWBUniversalPlatformPlugin.bundle/Contents/Frameworks/
  SWBUniversalPlatform.framework/Versions/A/Resources/Swift.xcspec
```

yields 19 `SWIFT_UPCOMING_FEATURE_*` keys. Mapped against the Notes' list:

| Upcoming feature | Xcode 26.6 build setting |
| --- | --- |
| `ExistentialAny` | `SWIFT_UPCOMING_FEATURE_EXISTENTIAL_ANY` |
| `InferIsolatedConformances` | `SWIFT_UPCOMING_FEATURE_INFER_ISOLATED_CONFORMANCES` |
| `InternalImportsByDefault` | `SWIFT_UPCOMING_FEATURE_INTERNAL_IMPORTS_BY_DEFAULT` |
| `MemberImportVisibility` | `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY` |
| `NonisolatedNonsendingByDefault` | `SWIFT_UPCOMING_FEATURE_NONISOLATED_NONSENDING_BY_DEFAULT` |
| **`ImmutableWeakCaptures`** | **none — no key exists** |

`ImmutableWeakCaptures` *is* a real feature in this toolchain — `swiftc -print-supported-features`
lists it under `upcoming` with `"enabled_in": "7"` — Xcode simply hasn't surfaced a build setting
for it yet. It therefore has to go through `OTHER_SWIFT_FLAGS`.

(Aside: `swiftc -enable-upcoming-feature BogusFeatureName -typecheck` exits 0 silently, so a typo in
a feature name fails open. `-print-supported-features` is the only reliable check.)

### `treatAllWarnings(as: .error)`

SwiftPM's `SwiftSetting.treatAllWarnings(as:)` maps to `-warnings-as-errors`
([SE-0480](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0480-swiftpm-warning-control.md))
and is available from swift-tools-version 6.2 — the Notes' `#if compiler(>=6.4)` guard is more
conservative than it needs to be. Under Tuist none of that matters: the Xcode setting is
`SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`, available today, no version guard.

### The verified answer: one helper, one project-level application

`Tuist/ProjectDescriptionHelpers/SimpleYNAB.swift`:

```swift
import ProjectDescription

public enum SimpleYNAB {
	/// Upcoming features Xcode 26.6 exposes as first-class build settings.
	public static let upcomingFeatureSettings: SettingsDictionary = [
		"SWIFT_UPCOMING_FEATURE_EXISTENTIAL_ANY": "YES",
		"SWIFT_UPCOMING_FEATURE_INFER_ISOLATED_CONFORMANCES": "YES",
		"SWIFT_UPCOMING_FEATURE_INTERNAL_IMPORTS_BY_DEFAULT": "YES",
		"SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY": "YES",
		"SWIFT_UPCOMING_FEATURE_NONISOLATED_NONSENDING_BY_DEFAULT": "YES",
	]

	/// Build settings shared by every target we own. `ImmutableWeakCaptures` has no
	/// `SWIFT_UPCOMING_FEATURE_*` key in Xcode 26.6, so it needs the raw flag — which is
	/// why this dictionary must never be handed to `PackageSettings`.
	public static let baseSettings: SettingsDictionary = upcomingFeatureSettings
		.merging([
			"SWIFT_VERSION": "6.0",
			"SWIFT_TREAT_WARNINGS_AS_ERRORS": "YES",
			"SWIFT_STRICT_CONCURRENCY": "complete",
			"OTHER_SWIFT_FLAGS": ["$(inherited)", "-enable-upcoming-feature", "ImmutableWeakCaptures"],
		])

	public static let deploymentTargets: DeploymentTargets = .multiplatform(
		iOS: "26.0",
		macOS: "26.0",
		watchOS: "26.0"
	)
}
```

Applied **once**, at project level:

```swift
let project = Project(
	name: "SimpleYNAB",
	settings: .settings(base: SimpleYNAB.baseSettings),
	targets: [ … ]
)
```

`Project.settings` is a real `Settings?`
([source](https://github.com/tuist/tuist/blob/4.202.6/cli/Sources/ProjectDescription/Project.swift)),
whose `base` dictionary "is inherited from all the configurations" and, through normal Xcode
inheritance, by every target in the project. **No per-target repetition is needed** — that is the
direct answer to the map's question.

**Verified.** `xcodebuild -showBuildSettings -scheme SimpleYNABKit` on the generated project:

```
EFFECTIVE_SWIFT_VERSION = 6
SWIFT_TREAT_WARNINGS_AS_ERRORS = YES
SWIFT_UPCOMING_FEATURE_EXISTENTIAL_ANY = YES
SWIFT_UPCOMING_FEATURE_INFER_ISOLATED_CONFORMANCES = YES
SWIFT_UPCOMING_FEATURE_INTERNAL_IMPORTS_BY_DEFAULT = YES
SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES
SWIFT_UPCOMING_FEATURE_NONISOLATED_NONSENDING_BY_DEFAULT = YES
OTHER_SWIFT_FLAGS = -enable-upcoming-feature ImmutableWeakCaptures -Xcc -fmodule-map-file=… \
                    -load-plugin-executable …#ComposableArchitectureMacros …
```

Note the last line: **`$(inherited)` composes correctly with the macro-plugin flags Tuist writes at
target level.** Setting `OTHER_SWIFT_FLAGS` at project level does not clobber macro support — this
was a live worry and it is unfounded *for our own targets* (it is emphatically not true for package
targets; see §4).

And the flags actually bite. Changing `func describe(_ value: any Describing)` to
`func describe(_ value: Describing)` produced:

```
error: use of protocol 'Describing' as a type must be written 'any Describing';
       this will be an error in a future Swift language mode
```

— an *error*, not a warning, i.e. `ExistentialAny` + `SWIFT_TREAT_WARNINGS_AS_ERRORS` are both live.

---

## 4. Can `packageSettings` apply the flags to external packages? Yes. Don't.

`PackageSettings` exposes exactly the hooks the ticket asks about
([source](https://github.com/tuist/tuist/blob/4.202.6/cli/Sources/ProjectDescription/PackageSettings.swift)):

```swift
public var baseSettings: Settings            // "base settings … for targets generated from SwiftPackageManager"
public var targetSettings: [String: Settings] // "Additional settings to be added to targets generated from SwiftPackageManager"
```

They work. `PackageSettings(baseSettings: .settings(base: …))` really does land on generated package
targets — `xcodebuild -showBuildSettings -target ComposableArchitecture` showed our
`SWIFT_UPCOMING_FEATURE_*` keys and `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` verbatim.

Three failures follow, all reproduced with `xcodebuild build`:

### 4a. `SWIFT_TREAT_WARNINGS_AS_ERRORS` collides with Tuist's own defaults

Tuist sets `SWIFT_SUPPRESS_WARNINGS = YES` and `GCC_WARN_INHIBIT_ALL_WARNINGS = YES` on every
generated package target (confirmed via `-showBuildSettings`). Adding warnings-as-errors gives the
driver contradictory flags:

```
error: Conflicting options '-warnings-as-errors' and '-suppress-warnings'
       (in target 'SwiftSyntax600' from project 'swift-syntax')
```

— nine such errors, across swift-syntax, GRDB, swift-collections, swift-sharing,
swift-concurrency-extras and xctest-dynamic-overlay.

### 4b. Setting `OTHER_SWIFT_FLAGS` **destroys** each package's own Swift settings

This is the sharp one, and it contradicts the "additive" reading of "base settings".
`PackageSettings.baseSettings` is merged by dictionary key into the generated targets, so an
`OTHER_SWIFT_FLAGS` entry *replaces* the value Tuist derived from the package's own
`swiftSettings`.

`InternalCollectionsUtilities` (swift-collections 1.6.0), **without** our `baseSettings`:

```
OTHER_SWIFT_FLAGS = -package-name swift-collections
  -enable-experimental-feature "AvailabilityMacro=SwiftStdlib 5.0: …"  (×13)
  -enable-upcoming-feature "MemberImportVisibility"
  -enable-experimental-feature "BuiltinModule"
  -enable-experimental-feature "Lifetimes"
  -enable-experimental-feature "InoutLifetimeDependence"
  -enable-experimental-feature "AddressableParameters"
  -enable-experimental-feature "AddressableTypes"
  -enable-experimental-feature "SuppressedAssociatedTypesWithDefaults"
```

**with** `PackageSettings(baseSettings: .settings(base: […, "OTHER_SWIFT_FLAGS": […]]))`:

```
OTHER_SWIFT_FLAGS = -enable-upcoming-feature ImmutableWeakCaptures -package-name swift-collections
                    -enable-upcoming-feature ImmutableWeakCaptures
```

Everything the package asked for is gone, and the build fails:

```
error: '@_lifetime' attribute is only valid when experimental feature Lifetimes is enabled
error: a function cannot return a ~Escapable result
```

`$(inherited)` does not save you here: our value replaced the target-level value that the package's
settings had been written into.

### 4c. Even the well-behaved `SWIFT_UPCOMING_FEATURE_*` keys break dependencies

Those keys are separate build settings, so they don't clobber anything — but our dependencies simply
aren't written against Swift 7 semantics. With only the five upcoming-feature keys applied through
`baseSettings` (no `OTHER_SWIFT_FLAGS`, no warnings-as-errors):

```
swift-concurrency-extras/Sources/ConcurrencyExtras/LockIsolated.swift:112:11:
  error: cannot use class 'NSRecursiveLock' in an extension with public or
         '@usableFromInline' members; 'Foundation' was not imported publicly
```

`InternalImportsByDefault` produces *errors*, not warnings, so `SWIFT_SUPPRESS_WARNINGS` cannot
absorb them.

### Conclusion

**Leave `PackageSettings` free of our Swift settings.** With `PackageSettings(baseProductType:
.staticFramework)` and the project-level `baseSettings` restricted to our own project, the macOS app
built clean (`** BUILD SUCCEEDED **`) with all six features enforced on first-party code. Our code
gets the strict regime; the dependencies get their authors' regime. That is the correct boundary
anyway — the flags exist to discipline code we write.

If a specific package ever needs a tweak, `PackageSettings.targetSettings["TargetName"]` is the
surgical tool, but avoid `OTHER_SWIFT_FLAGS` there for the reason in §4b.

---

## 5. Multi-platform targets and the watchOS constraint

A Tuist target carries a **set** of destinations, not a platform:
`public var destinations: Destinations` where `Destinations = Set<Destination>`
([source](https://github.com/tuist/tuist/blob/4.202.6/cli/Sources/ProjectDescription/Destination.swift)).
So a shared framework is **one target**, not one per platform.

**Verified.** `destinations: [.iPhone, .iPad, .mac, .appleWatch]` on a single `.framework` target
produced:

```
SUPPORTED_PLATFORMS      = iphoneos iphonesimulator macosx watchos watchsimulator
TARGETED_DEVICE_FAMILY   = 1,2,4
IPHONEOS_DEPLOYMENT_TARGET = 26.0
MACOSX_DEPLOYMENT_TARGET   = 26.0
WATCHOS_DEPLOYMENT_TARGET  = 26.0
```

and the iOS app built against it: `** BUILD SUCCEEDED **`.

### What this means for the watchOS-later constraint

**External package platforms are derived from the destinations of the first-party targets that
depend on them.** Verified by flipping the framework's destinations and re-reading the generated TCA
target:

| Framework destinations | `ComposableArchitecture` `SUPPORTED_PLATFORMS` |
| --- | --- |
| `[.iPhone, .iPad, .mac, .appleWatch]` | `iphoneos iphonesimulator macosx watchos watchsimulator` |
| `[.iPhone, .iPad, .mac]` | `iphoneos iphonesimulator macosx` |

So adding the Watch app in v2 is: add `.appleWatch` to the shared framework's `destinations`, add
`watchOS:` to its `deploymentTargets`, `tuist generate`. Every external package follows
automatically — no `Package.swift` edit, no per-platform target duplication.

**Guard rail found the hard way:** Tuist lints destinations against deployment targets and *fails*
generation on a mismatch:

```
[error] [TuistCore] Found an inconsistency between target destinations
        `[iPad, iPhone, mac]` and deployment target `watchOS`
[error] [TuistCore] Found deployment platforms (watchOS) missing corresponding destination
```

Practical consequence: a shared `SimpleYNAB.deploymentTargets` constant that names watchOS can only
be used on targets whose `destinations` include `.appleWatch`. The app targets need their own
narrower `.iOS("26.0")` / `.macOS("26.0")`.

**Not verified:** an actual watchOS compile. The watchOS 26.5 SDK is present
(`xcodebuild -showsdks`) but the platform runtime is not installed, so every watchOS destination
resolves to *"watchOS 26.5 is not installed. Please download and install the platform from
Xcode > Settings > Components."* Generation, `SUPPORTED_PLATFORMS` and package platform propagation
are verified; the compile is not. Install the watchOS platform before treating watchOS support as
proven.

**Note on product type.** The lab used `product: .framework` (dynamic) for the shared module while
the external packages are `.staticFramework`. That built and linked. If two apps plus a Watch
extension end up embedding the same dynamic framework, revisit — Tuist's guidance is "as many
things as possible statically linked in release builds … dynamically linked in debug builds"
([dependencies guide](https://tuist.dev/en/docs/guides/features/projects/dependencies)).

---

## 6. Generated project hygiene / `.gitignore`

Tuist writes into the repo:

| Path | Committed? |
| --- | --- |
| `SimpleYNAB.xcodeproj`, `SimpleYNAB.xcworkspace` | no — regenerate |
| `Derived/` (`InfoPlists/`, `ModuleMaps/`, synthesized resource accessors) | no |
| `Tuist/.build/` — SPM checkouts *and* the generated dependency projects under `tuist-derived/` | no (**1.0 GB** in the lab) |
| `Tuist/Package.resolved` | **yes** — it is the lockfile |
| `Tuist.swift`, `Project.swift`, `Tuist/Package.swift`, `Tuist/ProjectDescriptionHelpers/` | yes |
| `graph.dot` (from `tuist graph`) | no |

The docs are explicit about `Derived`: *"We recommend adding the `Derived` directory to the
`.gitignore` file of your project"*
([synthesized files](https://tuist.dev/en/docs/guides/features/projects/synthesized-files)).
Tuist's own repo `.gitignore` carries `**/Derived/`, `.build/`, `**/*.xcodeproj`,
`**/*.xcworkspace/*` ([source](https://github.com/tuist/tuist/blob/main/.gitignore)).

`Tuist/Package.resolved` should be tracked: Tuist's `OutdatedDependenciesAction` is documented as
firing when *"`Package.resolved` has changed since the last `tuist install`"*
([source](https://github.com/tuist/tuist/blob/4.202.6/cli/Sources/ProjectDescription/ConfigGenerationOptions.swift)),
which only makes sense for a tracked file.

**The repo's existing `.gitignore` already covers all of this** — `.build/`, `*.xcodeproj`,
`*.xcworkspace`, `Derived/`, `graph.dot`, `DerivedData/`. Nothing needs adding. (`.build/` without a
leading slash matches `Tuist/.build/` at any depth.)

### Pinning the Tuist version

Tuist is installed here via Homebrew cask (`/opt/homebrew/Caskroom/tuist/4.202.6`). Tuist's own docs
push mise instead, because *"Unlike tools like Homebrew, which install and activate a single version
of the tool globally, Mise pins a version either globally or scoped to a project"*
([install guide](https://tuist.dev/en/docs/guides/quick-start/install-tuist)), with the pin stored
in `mise.toml`. This repo pins SwiftFormat/SwiftLint through `Mintfile` and everything else through
`Brewfile`; an unpinned Tuist is the odd one out, since a Tuist minor bump can change generated
output. Either add `mise.toml` or pin the cask version — a decision for the scaffold ticket, not
settled here.

---

## 7. Coexisting with SwiftFormat / SwiftLint / lefthook

The generated `.xcodeproj`/`.xcworkspace`/`Derived` are gitignored, so lefthook's staged-file hooks
never see them. The *manifests*, though, are ordinary Swift files at the repo root and **are**
staged. Four findings, all run against this repo's actual configs (fetched
`brzzdev/Configs` base + local `.swiftformat` / `.swiftlint.yml`) with SwiftFormat 0.62.1 and
SwiftLint 0.65.0:

### 7a. `acronyms` corrupts `Project.swift` — this will break `just format` on day one

The base config enables `--rules acronyms`, whose defaults include `ID`. Running the repo's exact
formatter over `Project.swift` rewrote every `bundleId:` argument label to `bundleID:`:

```diff
-			bundleId: "dev.brzz.SimpleYNAB.Kit",
+			bundleID: "dev.brzz.SimpleYNAB.Kit",
```

and `tuist generate` then failed:

```
Project.swift:14:10: error: incorrect argument label in call
  (have 'name:destinations:product:bundleID:deploymentTargets:sources:dependencies:',
   expected 'name:destinations:product:bundleId:deploymentTargets:sources:dependencies:')
```

**Fix, verified:** add to the repo's `.swiftformat`

```
--preserve-acronyms bundleId
```

With that flag, re-running the formatter over the same `Project.swift` reported `0/1 files
formatted` and all four `bundleId:` labels survived. (Excluding the manifests wholesale also works
but loses formatting and the SPDX header on them.)

### 7b. `Tuist/Package.swift` never gets the SPDX header, and `format-check` is fine with that

SwiftFormat's `fileHeader` rule skips files beginning with `// swift-tools-version:`. Verified:
`swiftformat --lint` flagged `Project.swift:1:1: error: (fileHeader) …` but raised **no** fileHeader
error for `Tuist/Package.swift`. So `just format-check` stays green while that one file lacks the
AGPL SPDX identifier. Given `CLAUDE.md`'s "don't strip it" rule, add the header by hand *below* the
tools-version line, or accept the gap knowingly.

`Project.swift`, `Tuist.swift` and the helpers **do** get the SPDX header stamped, and Tuist parses
them fine with it (verified — generation succeeded with the header in place).

### 7c. Trailing commas in manifests are fine

`--rules trailingCommas` with `--swiftversion 6.3` adds trailing commas to function-call argument
lists (SE-0439). Tuist compiles manifests with the Xcode toolchain's swiftc (6.3.3), so
`.options(enforceExplicitDependencies: true,)` and friends parse. Verified: generation succeeded on
fully-formatted manifests.

### 7d. `Tuist/.build` is already excluded from both linters

Despite holding ~1 GB of package checkouts, neither tool descends into it — the shared configs carry
`--exclude …,.build,…` (SwiftFormat) and `excluded: ["**/.build"]` (SwiftLint), and both match at
any depth. Verified: `swiftformat .` reported `8 files`, `swiftlint --strict` reported
`Found 0 violations, 0 serious in 8 files` — exactly the eight first-party Swift files.

*Caveat:* if resource synthesizers are ever switched on, `Derived/Sources/*.swift` will appear and
**is not** currently excluded from SwiftLint. Add `Derived` to `.swiftlint_child.yml`'s `excluded`
at that point.

### 7e. Suggested `justfile` additions

```just
# Regenerate the Xcode project
generate:
	tuist install
	tuist generate --no-open

# Fail on implicit or redundant target dependencies (used by CI)
inspect:
	tuist inspect dependencies
```

`tuist inspect dependencies` is the supported replacement for the deprecated
`enforceExplicitDependencies` generation option, and it found a genuine implicit dependency in the
lab on first run.

---

## 8. Swift Testing targets

**Nothing special is required.** `Product.unitTests` exists
([source](https://github.com/tuist/tuist/blob/4.202.6/cli/Sources/ProjectDescription/Product.swift));
`import Testing` resolves from the toolchain; no package dependency, no test plan, no
`.uiTests` sibling.

```swift
.target(
	name: "SimpleYNABKitTests",
	destinations: [.iPhone, .iPad, .mac, .appleWatch],
	product: .unitTests,
	bundleId: "dev.brzz.SimpleYNAB.KitTests",
	deploymentTargets: SimpleYNAB.deploymentTargets,
	sources: ["Tests/SimpleYNABKitTests/**"],
	dependencies: [
		.target(name: "SimpleYNABKit"),
		.external(name: "ComposableArchitecture"), // TestStore — declare it, don't inherit it
	]
)
```

**Verified** with `tuist test SimpleYNABKit --platform macos`:

```
Test run started.
Suite EntryFeatureTests started
    ✔ amountChanges() (0.003 seconds)
Suite EntryFeatureTests passed after 0.003 seconds
Test Succeeded
```

Notes worth carrying forward:

- Tuist auto-generates a scheme named after the **framework** target (`SimpleYNABKit`) whose test
  action runs `SimpleYNABKitTests`. There is no `SimpleYNABKitTests` scheme — `tuist test
  SimpleYNABKitTests` errors with *"Couldn't find scheme"*. Pass the framework's name.
- The XCTest harness still emits `Executed 0 tests` alongside the Swift Testing run. Cosmetic.
- **Selective testing bites.** A second, unchanged `tuist test` printed *"The scheme SimpleYNABKit's
  test action has no tests to run, finishing early"* and exited 0 without running anything. Tuist
  hashes targets and skips unchanged tests. Use `--no-selective-testing` when you need a
  deterministic run (CI, or "did that actually run?").
- The test target's `destinations` must be a superset-compatible match for the framework's, and its
  `deploymentTargets` obey the §5 lint.

---

## Appendix — the verified `Project.swift`

Reproduced verbatim from the lab, minus the SPDX header. `tuist generate` + `xcodebuild build`
(macOS, iOS simulator) + `tuist test` all pass on it.

```swift
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
	name: "SimpleYNAB",
	organizationName: "brzzdev",
	settings: .settings(base: SimpleYNAB.baseSettings),
	targets: [
		.target(
			name: "SimpleYNABKit",
			destinations: [.iPhone, .iPad, .mac, .appleWatch],
			product: .framework,
			bundleId: "dev.brzz.SimpleYNAB.Kit",
			deploymentTargets: SimpleYNAB.deploymentTargets,
			sources: ["Sources/SimpleYNABKit/**"],
			dependencies: [
				.external(name: "ComposableArchitecture"),
				.external(name: "Dependencies"),
				.external(name: "SQLiteData"),
			]
		),
		.target(
			name: "SimpleYNABKitTests",
			destinations: [.iPhone, .iPad, .mac, .appleWatch],
			product: .unitTests,
			bundleId: "dev.brzz.SimpleYNAB.KitTests",
			deploymentTargets: SimpleYNAB.deploymentTargets,
			sources: ["Tests/SimpleYNABKitTests/**"],
			dependencies: [
				.target(name: "SimpleYNABKit"),
				.external(name: "ComposableArchitecture"),
			]
		),
		.target(
			name: "SimpleYNAB-iOS",
			destinations: .iOS,
			product: .app,
			bundleId: "dev.brzz.SimpleYNAB",
			deploymentTargets: .iOS("26.0"),
			infoPlist: .extendingDefault(with: [
				"UILaunchScreen": ["UIColorName": ""],
			]),
			sources: ["Apps/iOS/Sources/**"],
			dependencies: [.target(name: "SimpleYNABKit")]
		),
		.target(
			name: "SimpleYNAB-macOS",
			destinations: .macOS,
			product: .app,
			bundleId: "dev.brzz.SimpleYNAB",
			deploymentTargets: .macOS("26.0"),
			infoPlist: .extendingDefault(with: [
				"LSUIElement": true,
			]),
			sources: ["Apps/macOS/Sources/**"],
			dependencies: [.target(name: "SimpleYNABKit")]
		),
	]
)
```

Directory layout that goes with it:

```
Tuist.swift
Project.swift
Tuist/
	Package.swift
	Package.resolved          # committed
	ProjectDescriptionHelpers/
		SimpleYNAB.swift
Sources/SimpleYNABKit/**
Tests/SimpleYNABKitTests/**
Apps/iOS/Sources/**
Apps/macOS/Sources/**
```

---

## Open questions this research did not settle

- **A real watchOS build** — platform runtime not installed (§5).
- **Pinning Tuist's version** — mise vs Homebrew cask (§6).
- **`.framework` vs `.staticFramework`** for the shared module once three products embed it (§5).
- **Non-default SQLiteData traits** through Tuist's SPM integration (§2).
- Whether the SPDX header should be hand-added to `Tuist/Package.swift` (§7b).
