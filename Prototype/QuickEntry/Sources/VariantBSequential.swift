//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

// PROTOTYPE — throwaway.
//
// VARIANT B — "One thing at a time". Amount, then payee, then confirm. The
// claim: a form is slow because it asks you to aim; a wizard never makes you
// aim, because there is only ever one thing on screen. Account, date and
// category never get a step of their own — they are pre-filled and only appear
// on the confirm screen, where they can be corrected but usually aren't.

import SwiftUI

struct VariantSequential: View {
	@Bindable var draft: Draft
	@State private var step = Step.amount
	@FocusState private var isPayeeFocused: Bool

	private enum Step { case amount, payee, confirm }

	var body: some View {
		VStack(spacing: 0) {
			header
			switch step {
			case .amount: amountStep
			case .payee: payeeStep
			case .confirm: confirmStep
			}
		}
		.padding(14)
		.clearOfSwitcher()
		.onAppear { draft.amountEntry = .minorUnits }
	}

	private var header: some View {
		HStack {
			if step != .amount {
				Button {
					draft.bump()
					step = step == .confirm ? .payee : .amount
				} label: {
					Image(systemName: "chevron.left")
				}
				.buttonStyle(.plain)
			}
			Spacer()
			Text(stepLabel).font(.caption).foregroundStyle(.secondary)
			Spacer()
			// Balances the back chevron so the title stays centred.
			Image(systemName: "chevron.left").opacity(0)
		}
		.padding(.bottom, 8)
	}

	private var stepLabel: String {
		switch step {
		case .amount: "1 of 3 — amount"
		case .payee: "2 of 3 — payee"
		case .confirm: "3 of 3 — confirm"
		}
	}

	// MARK: 1 — amount

	private var amountStep: some View {
		VStack(spacing: 16) {
			Spacer(minLength: 0)
			Text(draft.formattedAmount)
				.font(.system(size: 48, weight: .semibold, design: .rounded))
				.contentTransition(.numericText())
				.foregroundStyle(draft.decimalAmount > 0 ? .primary : .tertiary)
			Picker("", selection: $draft.isInflow) {
				Text("Outflow").tag(false)
				Text("Inflow").tag(true)
			}
			.pickerStyle(.segmented)
			.labelsHidden()
			.onChange(of: draft.isInflow) { draft.bump() }
			Spacer(minLength: 0)
			Keypad(
				draft: draft,
				confirmLabel: "Next",
				isConfirmEnabled: draft.decimalAmount > 0
			) {
				draft.bump()
				step = .payee
				isPayeeFocused = true
			}
		}
		.capturingDigits(into: draft)
		// Return advances, so the whole amount step is reachable from the number row.
		.background {
			Button("") {
				guard draft.decimalAmount > 0 else { return }
				step = .payee
				isPayeeFocused = true
			}
			.keyboardShortcut(.return, modifiers: [])
			.opacity(0)
		}
	}

	// MARK: 2 — payee

	private var payeeStep: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text(draft.formattedAmount)
				.font(.title3.weight(.semibold))
				.foregroundStyle(.secondary)

			TextField("Who did you pay?", text: $draft.payeeQuery)
				.textFieldStyle(.roundedBorder)
				.font(.title3)
				.focused($isPayeeFocused)
				.onChange(of: draft.payeeQuery) {
					draft.bump()
					draft.payee = nil
				}
				.onSubmit(commitPayee)
				#if os(iOS)
				.autocorrectionDisabled()
				.textInputAutocapitalization(.words)
				#endif
				.task {
					try? await Task.sleep(for: .milliseconds(60))
					isPayeeFocused = true
				}

			// Recents are on screen before a single character is typed — the point
			// of the whole variant is that the common case needs no typing at all.
			ScrollView {
				VStack(alignment: .leading, spacing: 0) {
					ForEach(Fixtures.suggestedPayees(for: draft.payeeQuery, limit: 8)) { payee in
						Button {
							draft.choose(payee)
							step = .confirm
						} label: {
							HStack {
								Text(payee.name)
								Spacer()
								Text(payee.usualCategory)
									.font(.caption)
									.foregroundStyle(.secondary)
							}
							.contentShape(.rect)
							.padding(.vertical, 8)
						}
						.buttonStyle(.plain)
						Divider()
					}
					if draft.isNewPayee {
						Button {
							draft.bump()
							step = .confirm
						} label: {
							Label("Create “\(draft.payeeQuery)”", systemImage: "plus.circle")
								.padding(.vertical, 8)
						}
						.buttonStyle(.plain)
					}
				}
			}
		}
	}

	private func commitPayee() {
		if let first = Fixtures.suggestedPayees(for: draft.payeeQuery).first {
			draft.choose(first)
		} else {
			draft.bump()
		}
		step = .confirm
	}

	// MARK: 3 — confirm

	private var confirmStep: some View {
		VStack(alignment: .leading, spacing: 14) {
			VStack(alignment: .leading, spacing: 2) {
				Text(draft.formattedAmount)
					.font(.system(size: 40, weight: .semibold, design: .rounded))
				Text(draft.resolvedPayeeName)
					.font(.title3)
					.foregroundStyle(.secondary)
			}

			// The three pre-filled fields, shown once, at the only moment they can
			// be checked without costing anything.
			VStack(spacing: 0) {
				prefilledRow("creditcard", "Account", draft.account) {
					ForEach(Fixtures.accounts, id: \.self) { account in
						Button(account) {
							draft.bump()
							draft.account = account
						}
					}
				}
				Divider()
				prefilledRow("calendar", "Date", Calendar.current.isDateInToday(draft.date)
					? "Today"
					: draft.date.formatted(date: .abbreviated, time: .omitted)) {
						ForEach(0 ..< 7, id: \.self) { daysAgo in
							let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
							Button(day.formatted(.dateTime.weekday(.wide).day().month())) {
								draft.bump()
								draft.date = day
							}
						}
					}
				Divider()
				prefilledRow("tag", "Category", draft.category ?? "Uncategorised") {
					ForEach(Fixtures.categories, id: \.self) { category in
						Button(category) {
							draft.bump()
							draft.category = category
						}
					}
				}
			}
			.background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10))

			Spacer(minLength: 0)

			Button {
				draft.save()
				step = .amount
			} label: {
				Text("Save")
					.font(.headline)
					.frame(maxWidth: .infinity, minHeight: 44)
			}
			.buttonStyle(.borderedProminent)
			.keyboardShortcut(.return, modifiers: [])
		}
	}

	private func prefilledRow(
		_ icon: String,
		_ label: String,
		_ value: String,
		@ViewBuilder options: () -> some View
	) -> some View {
		Menu {
			options()
		} label: {
			HStack {
				Label(label, systemImage: icon)
					.font(.caption)
					.foregroundStyle(.secondary)
				Spacer()
				Text(value).font(.callout)
				Image(systemName: "chevron.up.chevron.down")
					.font(.caption2)
					.foregroundStyle(.tertiary)
			}
			.padding(.horizontal, 10)
			.padding(.vertical, 9)
			.contentShape(.rect)
		}
		.menuStyle(.button)
		.buttonStyle(.plain)
	}
}
