//
// Copyright © 2026 brzzdev
// SPDX-License-Identifier: AGPL-3.0-or-later
//

// PROTOTYPE — throwaway. No tests, no error handling, no abstractions.
// Fake data only; nothing here talks to YNAB.

import Foundation

// MARK: - Fixtures

struct Payee: Identifiable, Hashable, Sendable {
	let id: Int
	let name: String
	/// Lower is more recent. Every variant leans on recents in some way, so the
	/// ordering has to be plausible rather than alphabetical.
	let recency: Int
	/// The category YNAB last saw for this payee. This is the whole basis of the
	/// "which fields can be pre-filled well enough to ignore?" question — if it
	/// holds in practice, category never needs touching.
	let usualCategory: String
}

enum Fixtures {
	static let accounts = ["Current", "Amex", "Joint", "Cash"]

	static let categories = [
		"Groceries", "Eating Out", "Transport", "Fuel", "Coffee",
		"Household", "Subscriptions", "Clothing", "Health", "Gifts",
		"Hobbies", "Income",
	]

	static let payees: [Payee] = [
		Payee(id: 1, name: "Tesco", recency: 0, usualCategory: "Groceries"),
		Payee(id: 2, name: "Pret A Manger", recency: 1, usualCategory: "Coffee"),
		Payee(id: 3, name: "TfL", recency: 2, usualCategory: "Transport"),
		Payee(id: 4, name: "Sainsbury's", recency: 3, usualCategory: "Groceries"),
		Payee(id: 5, name: "Amazon", recency: 4, usualCategory: "Household"),
		Payee(id: 6, name: "Tesco Petrol", recency: 5, usualCategory: "Fuel"),
		Payee(id: 7, name: "The Blue Anchor", recency: 6, usualCategory: "Eating Out"),
		Payee(id: 8, name: "Boots", recency: 7, usualCategory: "Health"),
		Payee(id: 9, name: "Spotify", recency: 8, usualCategory: "Subscriptions"),
		Payee(id: 10, name: "Co-op", recency: 9, usualCategory: "Groceries"),
		Payee(id: 11, name: "Deliveroo", recency: 10, usualCategory: "Eating Out"),
		Payee(id: 12, name: "Waitrose", recency: 11, usualCategory: "Groceries"),
		Payee(id: 13, name: "Uniqlo", recency: 12, usualCategory: "Clothing"),
		Payee(id: 14, name: "Trainline", recency: 13, usualCategory: "Transport"),
		Payee(id: 15, name: "Screwfix", recency: 14, usualCategory: "Household"),
		Payee(id: 16, name: "Caffè Nero", recency: 15, usualCategory: "Coffee"),
		Payee(id: 17, name: "Shell", recency: 16, usualCategory: "Fuel"),
		Payee(id: 18, name: "Netflix", recency: 17, usualCategory: "Subscriptions"),
		Payee(id: 19, name: "Superdrug", recency: 18, usualCategory: "Health"),
		Payee(id: 20, name: "Marks & Spencer", recency: 19, usualCategory: "Groceries"),
		Payee(id: 21, name: "Wickes", recency: 20, usualCategory: "Household"),
		Payee(id: 22, name: "Greggs", recency: 21, usualCategory: "Eating Out"),
		Payee(id: 23, name: "Apple", recency: 22, usualCategory: "Subscriptions"),
		Payee(id: 24, name: "Zara", recency: 23, usualCategory: "Clothing"),
	]

	/// Recents first when the query is empty; otherwise prefix, then contains,
	/// then subsequence. This is *not* the payee-matching decision (that is still
	/// fog on the map) — it is just good enough to judge the shape of the UI.
	static func suggestedPayees(for query: String, limit: Int = 6) -> [Payee] {
		let byRecency = payees.sorted { $0.recency < $1.recency }
		let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
		guard !needle.isEmpty else { return Array(byRecency.prefix(limit)) }

		func rank(_ payee: Payee) -> Int? {
			let name = payee.name.lowercased()
			if name.hasPrefix(needle) { return 0 }
			if name.contains(needle) { return 1 }
			return isSubsequence(needle, of: name) ? 2 : nil
		}

		var ranked: [(payee: Payee, rank: Int)] = []
		for payee in byRecency {
			if let rank = rank(payee) { ranked.append((payee, rank)) }
		}
		ranked.sort { left, right in
			left.rank == right.rank ? left.payee.recency < right.payee.recency : left.rank < right.rank
		}
		return ranked.prefix(limit).map(\.payee)
	}

	private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
		var remaining = Substring(needle)
		for character in haystack where character == remaining.first {
			remaining = remaining.dropFirst()
			if remaining.isEmpty { return true }
		}
		return remaining.isEmpty
	}
}

// MARK: - Draft

/// How the variant currently on screen wants `amountText` interpreted.
enum AmountEntry {
	/// Card-terminal style: digits fill from the right, so "1234" means 12.34.
	/// No decimal point is ever typed.
	case minorUnits
	/// A plain decimal field: the user types "12.34" themselves.
	case freeText
}

struct SavedTransaction: Identifiable {
	let id = UUID()
	let summary: String
	let milliunits: Int
	/// Discrete user actions from first touch to save — the ticket asks for the
	/// minimum number of interactions, so the prototype counts them rather than
	/// asking anyone to guess.
	let interactions: Int
	let seconds: Double
}

@MainActor
@Observable
final class Draft {
	var amountEntry: AmountEntry = .freeText
	var amountText = ""
	var payeeQuery = ""
	var payee: Payee?
	var account = Fixtures.accounts[0]
	var date = Date.now
	var category: String?
	var isInflow = false

	private(set) var interactions = 0
	private(set) var startedAt: Date?
	private(set) var lastSaved: SavedTransaction?

	// MARK: Amount

	var decimalAmount: Decimal {
		switch amountEntry {
		case .minorUnits:
			let digits = amountText.filter(\.isNumber)
			return Decimal(Int(digits) ?? 0) / 100
		case .freeText:
			return Decimal(string: amountText.filter { $0.isNumber || $0 == "." }) ?? 0
		}
	}

	var formattedAmount: String {
		decimalAmount.formatted(.currency(code: "GBP"))
	}

	/// YNAB's wire format: outflow is negative, three decimal places.
	var milliunits: Int {
		let magnitude = NSDecimalNumber(decimal: decimalAmount * 1000).intValue
		return isInflow ? magnitude : -magnitude
	}

	// MARK: Editing

	/// Every discrete user action funnels through here so the interaction count
	/// and the clock are honest across all four variants.
	func bump(_ count: Int = 1) {
		if startedAt == nil { startedAt = .now }
		interactions += count
	}

	func appendDigit(_ digit: String) {
		bump()
		guard amountText.count < 9 else { return }
		amountText += digit
	}

	func deleteDigit() {
		bump()
		_ = amountText.popLast()
	}

	func choose(_ payee: Payee) {
		bump()
		self.payee = payee
		payeeQuery = payee.name
		// Pre-fill from what YNAB already knows about this payee. Whether this is
		// good enough to hide the category field entirely is the thing to judge.
		category = payee.usualCategory
	}

	/// A payee the user typed that YNAB has never seen. The API survey (#2)
	/// settled that this needs no pre-flight step — `payee_name` with a null
	/// `payee_id` creates it inline.
	var isNewPayee: Bool {
		payee == nil && !payeeQuery.trimmingCharacters(in: .whitespaces).isEmpty
	}

	var resolvedPayeeName: String {
		payee?.name ?? payeeQuery.trimmingCharacters(in: .whitespaces)
	}

	var canSave: Bool {
		decimalAmount > 0 && !resolvedPayeeName.isEmpty
	}

	// MARK: Saving

	func save() {
		guard canSave else { return }
		bump()
		lastSaved = SavedTransaction(
			summary: "\(isInflow ? "+" : "−")\(formattedAmount) · \(resolvedPayeeName) · \(account) · \(category ?? "Uncategorised")",
			milliunits: milliunits,
			interactions: interactions,
			seconds: startedAt.map { Date.now.timeIntervalSince($0) } ?? 0
		)
		reset()
	}

	/// Back to the state the app opens in. What "done" looks like — whether the
	/// window dismisses itself — is a variant-level choice, not this one.
	func reset() {
		amountText = ""
		payeeQuery = ""
		payee = nil
		account = Fixtures.accounts[0]
		date = .now
		category = nil
		isInflow = false
		interactions = 0
		startedAt = nil
	}
}
