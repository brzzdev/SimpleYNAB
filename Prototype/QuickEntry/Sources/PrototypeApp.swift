//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

// PROTOTYPE — throwaway.

import SwiftUI

@main
struct PrototypeApp: App {
	var body: some Scene {
		#if os(macOS)
		// The popover *is* the app: no Dock icon, no window (LSUIElement in the
		// manifest). A real build would open this on a global hotkey; clicking the
		// menu bar item is close enough to judge the layout.
		MenuBarExtra("QuickEntry", systemImage: "sterlingsign.circle.fill") {
			PrototypeShell()
				.frame(width: 340, height: 460)
		}
		.menuBarExtraStyle(.window)
		#else
		WindowGroup {
			PrototypeShell()
		}
		#endif
	}
}
