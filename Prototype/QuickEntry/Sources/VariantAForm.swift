//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

// PROTOTYPE — throwaway.
//
// VARIANT A — "Form". Everything is visible at once and nothing is a step. The
// claim: a transaction has six fields, so show six fields; speed comes from
// good defaults and tab order, not from hiding things.

import SwiftUI

struct VariantForm: View {
	@Bindable var draft: Draft
	@FocusState private var focus: Field?

	private enum Field { case amount, payee }

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			amountRow
			Divider()
			payeeRow
			if focus == .payee, draft.payee == nil {
				suggestions
			}
			Divider()
			chips
			Spacer(minLength: 0)
			saveButton
		}
		.padding(14)
		.clearOfSwitcher()
		.onAppear { draft.amountEntry = .freeText }
		// A bare `onAppear` lands before the field can take focus on iOS, which
		// would sink this variant's whole claim — the amount must be typeable the
		// instant the app is on screen.
		.task {
			try? await Task.sleep(for: .milliseconds(60))
			focus = .amount
		}
	}

	// MARK: Rows

	private var amountRow: some View {
		HStack(alignment: .firstTextBaseline, spacing: 6) {
			Button {
				draft.bump()
				draft.isInflow.toggle()
			} label: {
				Image(systemName: draft.isInflow ? "arrow.down.left.circle.fill" : "arrow.up.right.circle.fill")
					.foregroundStyle(draft.isInflow ? .green : .primary)
					.font(.title2)
			}
			.buttonStyle(.plain)
			.help("Toggle inflow / outflow")

			Text("£").font(.system(size: 30, weight: .light))
			TextField("0.00", text: $draft.amountText)
				.textFieldStyle(.plain)
				.font(.system(size: 34, weight: .medium, design: .rounded))
				.focused($focus, equals: .amount)
				.onSubmit { focus = .payee }
				.onChange(of: draft.amountText) { draft.bump() }
				#if os(iOS)
				.keyboardType(.decimalPad)
				#endif
		}
	}

	private var payeeRow: some View {
		HStack {
			Image(systemName: "person.crop.circle").foregroundStyle(.secondary)
			TextField("Payee", text: $draft.payeeQuery)
				.textFieldStyle(.plain)
				.font(.title3)
				.focused($focus, equals: .payee)
				.onChange(of: draft.payeeQuery) {
					draft.bump()
					draft.payee = nil
				}
				.onSubmit {
					if let first = Fixtures.suggestedPayees(for: draft.payeeQuery).first {
						draft.choose(first)
					}
					focus = nil
				}
				#if os(iOS)
				.autocorrectionDisabled()
				.textInputAutocapitalization(.words)
				#endif
			if draft.isNewPayee {
				Text("new").font(.caption2).foregroundStyle(.secondary)
			}
		}
	}

	private var suggestions: some View {
		VStack(alignment: .leading, spacing: 0) {
			ForEach(Fixtures.suggestedPayees(for: draft.payeeQuery, limit: 4)) { payee in
				Button {
					draft.choose(payee)
					focus = nil
				} label: {
					HStack {
						Text(payee.name)
						Spacer()
						Text(payee.usualCategory).font(.caption2).foregroundStyle(.secondary)
					}
					.contentShape(.rect)
					.padding(.vertical, 5)
				}
				.buttonStyle(.plain)
			}
		}
	}

	private var chips: some View {
		// Wraps rather than scrolls: on a 340pt popover all four have to be
		// reachable without a gesture.
		FlowRow(spacing: 6) {
			Menu {
				ForEach(Fixtures.accounts, id: \.self) { account in
					Button(account) {
						draft.bump()
						draft.account = account
					}
				}
			} label: {
				chipLabel("creditcard", draft.account, isMuted: false)
			}
			.menuStyle(.button)
			.buttonStyle(.plain)

			Menu {
				ForEach(0 ..< 7, id: \.self) { daysAgo in
					let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
					Button(dateLabel(day)) {
						draft.bump()
						draft.date = day
					}
				}
			} label: {
				chipLabel("calendar", dateLabel(draft.date), isMuted: Calendar.current.isDateInToday(draft.date))
			}
			.menuStyle(.button)
			.buttonStyle(.plain)

			Menu {
				ForEach(Fixtures.categories, id: \.self) { category in
					Button(category) {
						draft.bump()
						draft.category = category
					}
				}
			} label: {
				chipLabel("tag", draft.category ?? "Category", isMuted: draft.category == nil)
			}
			.menuStyle(.button)
			.buttonStyle(.plain)
		}
	}

	private func chipLabel(_ icon: String, _ text: String, isMuted: Bool) -> some View {
		HStack(spacing: 4) {
			Image(systemName: icon)
			Text(text).lineLimit(1)
		}
		.font(.caption)
		.padding(.horizontal, 8)
		.padding(.vertical, 5)
		.background(isMuted ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.tint.opacity(0.15)), in: .capsule)
	}

	private var saveButton: some View {
		Button {
			draft.save()
		} label: {
			Text("Save")
				.frame(maxWidth: .infinity)
				.padding(.vertical, 8)
		}
		.buttonStyle(.borderedProminent)
		.disabled(!draft.canSave)
		.keyboardShortcut(.return, modifiers: .command)
	}

	private func dateLabel(_ date: Date) -> String {
		let calendar = Calendar.current
		if calendar.isDateInToday(date) { return "Today" }
		if calendar.isDateInYesterday(date) { return "Yesterday" }
		return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
	}
}

/// Minimal wrapping row. `Layout` beats an HStack here because the chips have
/// unpredictable widths and a 340pt popover has no room to spare.
struct FlowRow: Layout {
	var spacing: CGFloat = 6

	func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
		let maxWidth = proposal.width ?? .infinity
		var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
		for subview in subviews {
			let size = subview.sizeThatFits(.unspecified)
			if x > 0, x + size.width > maxWidth {
				x = 0
				y += rowHeight + spacing
				rowHeight = 0
			}
			x += size.width + spacing
			rowHeight = max(rowHeight, size.height)
		}
		return CGSize(width: maxWidth, height: y + rowHeight)
	}

	func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
		let maxWidth = proposal.width ?? bounds.width
		var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
		for subview in subviews {
			let size = subview.sizeThatFits(.unspecified)
			if x > bounds.minX, x - bounds.minX + size.width > maxWidth {
				x = bounds.minX
				y += rowHeight + spacing
				rowHeight = 0
			}
			subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
			x += size.width + spacing
			rowHeight = max(rowHeight, size.height)
		}
	}
}
