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

# Install developer tools
tools:
	which brew || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
	brew bundle install
	mint bootstrap
	just install-hooks
