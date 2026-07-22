//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

// PROTOTYPE — throwaway. The chrome is deliberately ugly so it can't be mistaken
// for the design being judged.

import SwiftUI

enum Variant: String, CaseIterable, Identifiable {
	case form = "A"
	case sequential = "B"
	case commandLine = "C"
	case payeeFirst = "D"

	var id: String { rawValue }

	var title: String {
		switch self {
		case .form: "Form"
		case .sequential: "One thing at a time"
		case .commandLine: "One line"
		case .payeeFirst: "Payee first"
		}
	}

	/// The structural claim each variant is making, so it can be argued with.
	var claim: String {
		switch self {
		case .form: "Everything visible at once. Nothing is hidden, nothing is a step."
		case .sequential: "Amount, then payee, then confirm. One decision per screen."
		case .commandLine: "Type the whole transaction as a single line. Enter saves."
		case .payeeFirst: "You know who you paid before you know what you paid. Pick, then type."
		}
	}
}

struct PrototypeShell: View {
	@AppStorage("prototype.variant") private var storedVariant = Variant.form.rawValue
	@State private var draft = Draft()
	@State private var isShowingState = false

	private var variant: Variant {
		Variant(rawValue: storedVariant) ?? .form
	}

	var body: some View {
		ZStack(alignment: .bottom) {
			Group {
				switch variant {
				case .form: VariantForm(draft: draft)
				case .sequential: VariantSequential(draft: draft)
				case .commandLine: VariantCommandLine(draft: draft)
				case .payeeFirst: VariantPayeeFirst(draft: draft)
				}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)

			switcher
		}
		.overlay(alignment: .top) { savedBanner }
		// A fresh draft per variant, so the interaction count is per-variant and
		// never carries state across a switch.
		.onChange(of: storedVariant) { draft.reset() }
		.background(shortcuts)
	}

	// MARK: Switcher

	private var switcher: some View {
		VStack(spacing: 0) {
			if isShowingState { stateReadout }

			HStack(spacing: 8) {
				Button { cycle(-1) } label: { Image(systemName: "chevron.left") }
				Text("\(variant.rawValue) — \(variant.title)")
					.font(.caption.monospaced())
					.lineLimit(1)
					.frame(maxWidth: .infinity)
				Button { cycle(1) } label: { Image(systemName: "chevron.right") }
				Button { isShowingState.toggle() } label: {
					Image(systemName: isShowingState ? "eye.fill" : "eye")
				}
				#if os(macOS)
				Button { NSApplication.shared.terminate(nil) } label: { Image(systemName: "power") }
				#endif
			}
			.buttonStyle(.plain)
			.font(.caption)
			.padding(.horizontal, 10)
			.padding(.vertical, 6)
		}
		.background(.black.opacity(0.85))
		.foregroundStyle(.white)
		.clipShape(.rect(cornerRadius: 10))
		.shadow(radius: 6)
		.padding(8)
	}

	private func cycle(_ step: Int) {
		let all = Variant.allCases
		let index = all.firstIndex(of: variant) ?? 0
		storedVariant = all[(index + step + all.count) % all.count].rawValue
	}

	/// Requirement 5 of the skill: surface the full state after every action.
	private var stateReadout: some View {
		VStack(alignment: .leading, spacing: 2) {
			Text(variant.claim)
				.font(.caption2)
				.foregroundStyle(.white.opacity(0.6))
			readoutRow("milliunits", "\(draft.milliunits)")
			readoutRow("payee", draft.resolvedPayeeName.isEmpty
				? "—"
				: "\(draft.resolvedPayeeName)\(draft.isNewPayee ? "  (new — created inline)" : "")")
			readoutRow("account", draft.account)
			readoutRow("date", draft.date.formatted(date: .abbreviated, time: .omitted))
			readoutRow("category", draft.category ?? "—")
			readoutRow("direction", draft.isInflow ? "inflow" : "outflow")
			readoutRow("interactions", "\(draft.interactions)")
		}
		.font(.caption2.monospaced())
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(10)
		.background(.white.opacity(0.08))
	}

	private func readoutRow(_ key: String, _ value: String) -> some View {
		HStack(alignment: .firstTextBaseline, spacing: 6) {
			Text(key).foregroundStyle(.white.opacity(0.5)).frame(width: 76, alignment: .leading)
			Text(value)
		}
	}

	// MARK: Saved banner

	@ViewBuilder
	private var savedBanner: some View {
		if let saved = draft.lastSaved {
			VStack(alignment: .leading, spacing: 2) {
				Label("Saved", systemImage: "checkmark.circle.fill")
					.font(.caption.bold())
				Text(saved.summary).font(.caption2)
				Text("\(saved.interactions) interactions · \(saved.seconds, format: .number.precision(.fractionLength(1)))s · \(saved.milliunits) milliunits")
					.font(.caption2.monospaced())
					.foregroundStyle(.secondary)
			}
			.padding(10)
			.frame(maxWidth: .infinity, alignment: .leading)
			.background(.green.opacity(0.18), in: .rect(cornerRadius: 10))
			.padding(8)
			.transition(.move(edge: .top).combined(with: .opacity))
			.id(saved.id)
		}
	}

	// MARK: Shortcuts

	/// ⌘[ / ⌘] cycle variants without stealing arrow keys from a focused field.
	private var shortcuts: some View {
		ZStack {
			Button("") { cycle(-1) }.keyboardShortcut("[", modifiers: .command)
			Button("") { cycle(1) }.keyboardShortcut("]", modifiers: .command)
		}
		.opacity(0)
	}
}

// MARK: - Shared bits

/// The minor-units amount control, shared by B and D so the two are comparing
/// layout rather than key size. Digits fill from the right — "1234" is £12.34
/// and no decimal point is ever typed.
///
/// The *model* is the same on both platforms; only the input surface differs. A
/// 3×4 grid of mouse targets is strictly slower than the number row, and in a
/// 340×460 popover it is also the only thing that fits — so macOS gets the
/// keyboard path and a confirm button instead.
struct Keypad: View {
	@Bindable var draft: Draft
	/// Rendered as the bottom-right key. The variants disagree about what
	/// finishing means, so they supply their own.
	let confirmLabel: String
	let isConfirmEnabled: Bool
	let confirm: () -> Void

	private let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]]

	var body: some View {
		#if os(macOS)
		keyboardPath
		#else
		grid
		#endif
	}

	private var keyboardPath: some View {
		VStack(spacing: 8) {
			Text("Type the amount — digits fill from the right, ⌫ deletes")
				.font(.caption)
				.foregroundStyle(.tertiary)
			Button(action: confirm) {
				Text(confirmLabel)
					.font(.headline)
					.frame(maxWidth: .infinity, minHeight: 30)
			}
			.buttonStyle(.borderedProminent)
			.disabled(!isConfirmEnabled)
		}
	}

	private var grid: some View {
		Grid(horizontalSpacing: 8, verticalSpacing: 8) {
			ForEach(rows, id: \.self) { row in
				GridRow {
					ForEach(row, id: \.self) { digit in
						key(digit) { draft.appendDigit(digit) }
					}
				}
			}
			GridRow {
				key("⌫") { draft.deleteDigit() }
				key("0") { draft.appendDigit("0") }
				Button(action: confirm) {
					Text(confirmLabel)
						.font(.headline)
						.frame(maxWidth: .infinity, minHeight: 52)
				}
				.buttonStyle(.borderedProminent)
				.disabled(!isConfirmEnabled)
			}
		}
	}

	private func key(_ label: String, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Text(label)
				.font(.system(size: 24, weight: .regular, design: .rounded))
				.frame(maxWidth: .infinity, minHeight: 52)
				.contentShape(.rect)
		}
		.buttonStyle(.bordered)
	}
}

/// Captures digits from a hardware keyboard so the minor-units entry model can
/// be judged on macOS too, not just under a thumb.
struct DigitCapture: ViewModifier {
	@Bindable var draft: Draft
	@FocusState private var isFocused: Bool

	func body(content: Content) -> some View {
		#if os(macOS)
		content
			.focusable()
			.focusEffectDisabled()
			.focused($isFocused)
			.onAppear { isFocused = true }
			.onKeyPress { press in
				if let character = press.characters.first, character.isNumber {
					draft.appendDigit(String(character))
					return .handled
				}
				if press.key == .delete {
					draft.deleteDigit()
					return .handled
				}
				return .ignored
			}
		#else
		content
		#endif
	}
}

extension View {
	func capturingDigits(into draft: Draft) -> some View {
		modifier(DigitCapture(draft: draft))
	}
}

extension View {
	/// Leaves room for the floating switcher so it never covers a variant's own
	/// primary action.
	func clearOfSwitcher() -> some View {
		safeAreaPadding(.bottom, 44)
	}
}
