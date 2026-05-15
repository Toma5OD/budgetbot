import Foundation
import SwiftData

/// A thing the user wants to buy / save for, in their own words. Distinct
/// from `SavingsGoal` in two ways:
///
///   - **No contributions** — dreams aren't actively funded; they're
///     reference points used to *quantify* spending choices ("your
///     €1,800 of alcohol this year = 36% of an engagement ring").
///   - **No deadline** — dreams sit there as long as you want. Once
///     `achievedAt` is set, the counterfactual engine moves it to a
///     "Done" pile.
///
/// SwiftData / CloudKit-friendly: every stored property is defaulted,
/// no `@Attribute(.unique)` beyond the auto id.
@Model
final class UserDream {
    var id: UUID = UUID()
    var name: String = ""
    var emoji: String = "🎯"
    var targetPrice: Decimal = 0
    var currency: String = "EUR"
    var note: String?
    var createdAt: Date = Date.now
    var achievedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        emoji: String = "🎯",
        targetPrice: Decimal,
        currency: String = "EUR",
        note: String? = nil,
        createdAt: Date = .now,
        achievedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.targetPrice = targetPrice
        self.currency = currency
        self.note = note
        self.createdAt = createdAt
        self.achievedAt = achievedAt
    }
}
