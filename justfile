# Run recipes under bash with pipefail so a failing xcodebuild isn't masked by a
# successful `| xcbeautify` (which would otherwise let CI go green on a red build).
set shell := ["bash", "-euo", "pipefail", "-c"]

swiftformat_base := "/tmp/swiftformat-base"

# List available recipes
default:
	@just --list

[private]
fetch-swiftformat-config:
	curl -sL https://raw.githubusercontent.com/brzzdev/Configs/main/Configs/swiftformat -o {{ swiftformat_base }}

# Format Swift sources
format: fetch-swiftformat-config
	mint run swiftformat . --base-config {{ swiftformat_base }}

# Fail if sources are unformatted or missing their SPDX header (used by CI)
format-check: fetch-swiftformat-config
	mint run swiftformat . --lint --base-config {{ swiftformat_base }}

# Format only the staged Swift hunks (used by the lefthook pre-commit hook)
[private]
format-staged: fetch-swiftformat-config
	./.git-format-staged --formatter "$(mint which swiftformat 2>/dev/null | tail -1) stdin --stdinpath '{}' --base-config {{ swiftformat_base }}" "*.swift"

# Install git hooks via lefthook
install-hooks:
	lefthook install

# Run SwiftLint
lint:
	mint run swiftlint --quiet --strict

# Show outdated Swift packages
outdated:
	mint run swift-outdated --ignore-prerelease

# PROTOTYPE ONLY — quick-entry variants on the iOS simulator (issue #4)
prototype-ios sim="iPhone 17 Pro":
	cd Prototype/QuickEntry && tuist generate --no-open
	cd Prototype/QuickEntry && xcodebuild -workspace QuickEntryPrototype.xcworkspace -scheme QuickEntryiOS -destination "platform=iOS Simulator,name={{ sim }}" -derivedDataPath .build -quiet build
	xcrun simctl boot "{{ sim }}" || true
	open -a Simulator
	# Without this, install/launch can race a still-booting device.
	xcrun simctl bootstatus booted -b
	xcrun simctl install booted Prototype/QuickEntry/.build/Build/Products/Debug-iphonesimulator/QuickEntryiOS.app
	xcrun simctl launch booted dev.brzz.SimpleYNAB.QuickEntryPrototype

# PROTOTYPE ONLY — quick-entry variants in the macOS menu bar (issue #4)
prototype-mac:
	cd Prototype/QuickEntry && tuist generate --no-open
	cd Prototype/QuickEntry && xcodebuild -workspace QuickEntryPrototype.xcworkspace -scheme QuickEntryMac -destination 'platform=macOS' -derivedDataPath .build -quiet build
	killall QuickEntryMac 2>/dev/null || true
	open Prototype/QuickEntry/.build/Build/Products/Debug/QuickEntryMac.app

# Install developer tools
tools:
	which brew || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
	brew bundle install
	mint bootstrap
	just install-hooks
