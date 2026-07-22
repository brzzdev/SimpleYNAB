import ProjectDescription

// THROWAWAY — see Tuist.swift. Two app targets compiling the same sources, so
// the four variants are judged on both surfaces without a shared-framework
// decision leaking into the real scaffold.
let sources: SourceFilesList = ["Sources/**"]

let project = Project(
	name: "QuickEntryPrototype",
	targets: [
		.target(
			name: "QuickEntryMac",
			destinations: [.mac],
			product: .app,
			bundleId: "dev.brzz.SimpleYNAB.QuickEntryPrototype",
			deploymentTargets: .macOS("26.0"),
			infoPlist: .extendingDefault(with: [
				// Menu-bar only: no Dock icon, no main window. The popover is the app.
				"LSUIElement": true,
				"CFBundleDisplayName": "QuickEntry Prototype",
			]),
			sources: sources
		),
		.target(
			name: "QuickEntryiOS",
			destinations: [.iPhone],
			product: .app,
			bundleId: "dev.brzz.SimpleYNAB.QuickEntryPrototype",
			deploymentTargets: .iOS("26.0"),
			infoPlist: .extendingDefault(with: [
				"UILaunchScreen": [:],
				"CFBundleDisplayName": "QuickEntry",
			]),
			sources: sources
		),
	]
)
