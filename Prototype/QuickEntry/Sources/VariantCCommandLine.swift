//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

// PROTOTYPE — throwaway.
//
// VARIANT C — "One line". The whole transaction is one string: `12.34 tesco
// @amex #groceries yesterday`. The claim: if you can already touch-type, no
// arrangement of fields beats never leaving the keyboard. The obvious cost is
// that it has to be learned, and that it is a poor fit for a thumb — both of
// which are exactly what this variant is here to expose.

import SwiftUI

struct VariantCommandLine: View {
	@Bindable var draft: Draft
	@State private var line = ""
	@FocusState private var isFocused: Bool

	private var parsed: ParsedLine { ParsedLine(line) }

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			field
			tokens
			Spacer(minLength: 0)
			grammar
		}
		.padding(14)
		.clearOfSwitcher()
		.onAppear { draft.amountEntry = .freeText }
		.task {
			try? await Task.sleep(for: .milliseconds(60))
			isFocused = true
		}
		.onChange(of: line) {
			draft.bump()
			apply(parsed)
		}
	}

	// MARK: Field

	private var field: some View {
		HStack(spacing: 6) {
			Image(systemName: "chevron.right")
				.font(.system(.body, design: .monospaced))
				.foregroundStyle(.tertiary)

			ZStack(alignment: .leading) {
				// The ghosted completion sits behind the field, so accepting it with
				// Tab feels like the text was already there.
				if let completion = parsed.payeeCompletion(from: line) {
					Text("\(Text(line).foregroundStyle(.clear))\(Text(completion).foregroundStyle(.tertiary))")
				}
				TextField("12.34 tesco", text: $line)
					.textFieldStyle(.plain)
					.onSubmit(save)
					#if os(iOS)
					.autocorrectionDisabled()
					.textInputAutocapitalization(.never)
					#endif
			}
			.font(.system(size: 20, design: .monospaced))
			.focused($isFocused)
		}
		.padding(10)
		.background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
		#if os(macOS)
			.onKeyPress(.tab) {
				guard let completion = parsed.payeeCompletion(from: line) else { return .ignored }
				line += completion
				return .handled
			}
		#endif
			.overlay(alignment: .trailing) {
				if draft.canSave {
					Text("⏎")
						.font(.caption)
						.foregroundStyle(.secondary)
						.padding(.trailing, 12)
				}
			}
	}

	// MARK: Feedback

	/// Everything the line resolved to, materialised as it is typed. Without this
	/// the variant is unusable — you cannot trust a parser you cannot see.
	private var tokens: some View {
		FlowRow(spacing: 6) {
			token("sterlingsign", draft.decimalAmount > 0 ? draft.formattedAmount : "amount", isSet: draft.decimalAmount > 0)
			token("person.crop.circle", draft.resolvedPayeeName.isEmpty ? "payee" : draft.resolvedPayeeName, isSet: !draft.resolvedPayeeName.isEmpty)
			token("creditcard", draft.account, isSet: parsed.account != nil)
			token("calendar", Calendar.current.isDateInToday(draft.date) ? "today" : draft.date.formatted(.dateTime.day().month(.abbreviated)), isSet: parsed.daysAgo != nil)
			token("tag", draft.category ?? "category", isSet: draft.category != nil)
			if draft.isInflow {
				token("arrow.down.left", "inflow", isSet: true)
			}
			if draft.isNewPayee {
				token("plus.circle", "new payee", isSet: true)
			}
		}
	}

	private func token(_ icon: String, _ text: String, isSet: Bool) -> some View {
		HStack(spacing: 4) {
			Image(systemName: icon)
			Text(text).lineLimit(1)
		}
		.font(.caption)
		.foregroundStyle(isSet ? .primary : .tertiary)
		.padding(.horizontal, 8)
		.padding(.vertical, 5)
		.background(isSet ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.quaternary.opacity(0.4)), in: .capsule)
	}

	private var grammar: some View {
		VStack(alignment: .leading, spacing: 3) {
			Text("amount payee  @account  #category  +inflow  today|yesterday|3d")
			Text("⇥ completes the payee · ⏎ saves")
		}
		.font(.caption2.monospaced())
		.foregroundStyle(.tertiary)
	}

	// MARK: Wiring

	private func apply(_ parsed: ParsedLine) {
		draft.amountText = parsed.amount ?? ""
		draft.isInflow = parsed.isInflow
		draft.payeeQuery = parsed.payeeQuery
		draft.payee = parsed.payeeQuery.isEmpty
			? nil
			: Fixtures.suggestedPayees(for: parsed.payeeQuery, limit: 1).first
		draft.account = parsed.account ?? Fixtures.accounts[0]
		draft.category = parsed.category ?? draft.payee?.usualCategory
		draft.date = Calendar.current.date(byAdding: .day, value: -(parsed.daysAgo ?? 0), to: .now) ?? .now
	}

	private func save() {
		guard draft.canSave else { return }
		draft.save()
		line = ""
	}
}

// MARK: - Parser

/// Deliberately dumb. The question is whether typing a line *feels* right, not
/// whether the grammar is any good — a real one would need far more care.
struct ParsedLine {
	var amount: String?
	var payeeQuery = ""
	var account: String?
	var category: String?
	var daysAgo: Int?
	var isInflow = false

	init(_ line: String) {
		var payeeWords: [String] = []

		for token in line.split(separator: " ").map(String.init) {
			switch token.first {
			case "@":
				account = Self.match(String(token.dropFirst()), in: Fixtures.accounts)
			case "#":
				category = Self.match(String(token.dropFirst()), in: Fixtures.categories)
			case "+" where token.dropFirst().allSatisfy { $0.isNumber || $0 == "." }:
				isInflow = true
				if amount == nil, token.count > 1 { amount = String(token.dropFirst()) }
			default:
				if amount == nil, token.allSatisfy({ $0.isNumber || $0 == "." }), token.contains(where: \.isNumber) {
					amount = token
				} else if let days = Self.days(from: token) {
					daysAgo = days
				} else {
					payeeWords.append(token)
				}
			}
		}

		payeeQuery = payeeWords.joined(separator: " ")
	}

	/// The remaining characters of the best payee match, for the ghosted
	/// completion. Only offered when the typed text is a genuine prefix —
	/// completing a fuzzy match mid-word is disorienting.
	func payeeCompletion(from line: String) -> String? {
		guard !payeeQuery.isEmpty, !line.hasSuffix(" ") else { return nil }
		guard let best = Fixtures.suggestedPayees(for: payeeQuery, limit: 1).first else { return nil }
		guard best.name.lowercased().hasPrefix(payeeQuery.lowercased()),
		      best.name.count > payeeQuery.count else { return nil }
		return String(best.name.dropFirst(payeeQuery.count))
	}

	private static func match(_ needle: String, in candidates: [String]) -> String? {
		guard !needle.isEmpty else { return nil }
		let lowered = needle.lowercased()
		return candidates.first { $0.lowercased().hasPrefix(lowered) }
			?? candidates.first { $0.lowercased().contains(lowered) }
	}

	private static func days(from token: String) -> Int? {
		switch token.lowercased() {
		case "today": 0
		case "yesterday", "yday": 1
		default:
			token.hasSuffix("d") ? Int(token.dropLast()) : nil
		}
	}
}
