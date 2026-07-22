//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

// PROTOTYPE — throwaway.
//
// VARIANT D — "Payee first". The order is inverted: you are standing at a till
// and you know *who* before you know *how much* — and the payee is the field
// that also fixes the category. So pick the payee from a grid of recents (one
// tap, no typing), then type the amount into a keypad that is already the only
// thing on screen. Nothing else is ever shown unless you ask for it.

import SwiftUI

struct VariantPayeeFirst: View {
	@Bindable var draft: Draft
	@State private var phase = Phase.payee
	@FocusState private var isSearchFocused: Bool

	private enum Phase { case payee, amount }

	var body: some View {
		Group {
			switch phase {
			case .payee: payeeGrid
			case .amount: amountPad
			}
		}
		.padding(14)
		.clearOfSwitcher()
		.onAppear { draft.amountEntry = .minorUnits }
	}

	// MARK: 1 — who

	private var payeeGrid: some View {
		VStack(spacing: 10) {
			TextField("Search or add a payee", text: $draft.payeeQuery)
				.textFieldStyle(.roundedBorder)
				.focused($isSearchFocused)
				.onChange(of: draft.payeeQuery) {
					draft.bump()
					draft.payee = nil
				}
				.onSubmit {
					if let first = Fixtures.suggestedPayees(for: draft.payeeQuery).first {
						pick(first)
					} else if draft.isNewPayee {
						draft.bump()
						phase = .amount
					}
				}
				#if os(iOS)
				.autocorrectionDisabled()
				.textInputAutocapitalization(.words)
				#endif

			ScrollView {
				LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
					if draft.isNewPayee {
						tile(title: draft.payeeQuery, subtitle: "New payee", isNew: true) {
							draft.bump()
							phase = .amount
						}
					}
					ForEach(Fixtures.suggestedPayees(for: draft.payeeQuery, limit: 12)) { payee in
						tile(title: payee.name, subtitle: payee.usualCategory, isNew: false) {
							pick(payee)
						}
					}
				}
			}
			.scrollIndicators(.never)
		}
	}

	private func tile(title: String, subtitle: String, isNew: Bool, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			VStack(alignment: .leading, spacing: 3) {
				Image(systemName: isNew ? "plus.circle" : "person.crop.circle.fill")
					.foregroundStyle(.tint)
				Text(title)
					.font(.callout.weight(.medium))
					.lineLimit(2, reservesSpace: true)
					.multilineTextAlignment(.leading)
				Text(subtitle)
					.font(.caption2)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(8)
			.background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10))
			.contentShape(.rect)
		}
		.buttonStyle(.plain)
	}

	private func pick(_ payee: Payee) {
		draft.choose(payee)
		phase = .amount
	}

	// MARK: 2 — how much

	private var amountPad: some View {
		VStack(spacing: 12) {
			HStack {
				Button {
					draft.bump()
					phase = .payee
				} label: {
					Label(draft.resolvedPayeeName, systemImage: "chevron.left")
						.font(.headline)
						.lineLimit(1)
				}
				.buttonStyle(.plain)
				Spacer()
			}

			// The pre-filled fields, as small as they can be while still being
			// visible. The bet is that you will never touch them.
			FlowRow(spacing: 6) {
				Menu {
					ForEach(Fixtures.accounts, id: \.self) { account in
						Button(account) {
							draft.bump()
							draft.account = account
						}
					}
				} label: { chip("creditcard", draft.account) }
					.menuStyle(.button).buttonStyle(.plain)

				Menu {
					ForEach(0 ..< 7, id: \.self) { daysAgo in
						let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
						Button(day.formatted(.dateTime.weekday(.wide).day().month())) {
							draft.bump()
							draft.date = day
						}
					}
				} label: {
					chip("calendar", Calendar.current.isDateInToday(draft.date)
						? "Today"
						: draft.date.formatted(.dateTime.day().month(.abbreviated)))
				}
				.menuStyle(.button).buttonStyle(.plain)

				Menu {
					ForEach(Fixtures.categories, id: \.self) { category in
						Button(category) {
							draft.bump()
							draft.category = category
						}
					}
				} label: { chip("tag", draft.category ?? "Uncategorised") }
					.menuStyle(.button).buttonStyle(.plain)

				Button {
					draft.bump()
					draft.isInflow.toggle()
				} label: {
					chip(draft.isInflow ? "arrow.down.left" : "arrow.up.right", draft.isInflow ? "Inflow" : "Outflow")
				}
				.buttonStyle(.plain)
			}

			Spacer(minLength: 0)

			Text(draft.formattedAmount)
				.font(.system(size: 46, weight: .semibold, design: .rounded))
				.contentTransition(.numericText())
				.foregroundStyle(draft.decimalAmount > 0 ? .primary : .tertiary)

			Spacer(minLength: 0)

			Keypad(
				draft: draft,
				confirmLabel: "Save",
				isConfirmEnabled: draft.canSave,
				confirm: save
			)
		}
		.capturingDigits(into: draft)
		.background {
			Button("", action: save)
				.keyboardShortcut(.return, modifiers: [])
				.opacity(0)
		}
	}

	private func chip(_ icon: String, _ text: String) -> some View {
		HStack(spacing: 4) {
			Image(systemName: icon)
			Text(text).lineLimit(1)
		}
		.font(.caption)
		.padding(.horizontal, 8)
		.padding(.vertical, 5)
		.background(.quaternary.opacity(0.5), in: .capsule)
	}

	private func save() {
		guard draft.canSave else { return }
		draft.save()
		phase = .payee
	}
}
