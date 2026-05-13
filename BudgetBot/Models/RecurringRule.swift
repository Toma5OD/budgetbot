import Foundation
import SwiftData

/// A detected (or, in future, user-defined) recurring payment pattern —
/// Netflix, electricity, rent. Detected at runtime by `SubscriptionDetector`
/// and persisted so the user can confirm / dismiss without re-detection.
@Model
final class RecurringRule {
    @Attribute(.unique) var id: UUID
    var payeePattern: String          // normalised payee match key
    var displayName: String           // shown in UI; defaults to payee
    var expectedAmount: Decimal       // signed (negative for expenses)
    var currency: String
    var cadenceRaw: String            // "monthly" | "weekly" | "yearly"
    var firstSeen: Date
    var lastSeen: Date
    var occurrences: Int
    var dismissed: Bool
    var createdAt: Date

    @Relationship var category: TxCategory?
    @Relationship var account: Account?

    init(
        id: UUID = UUID(),
        payeePattern: String,
        displayName: String,
        expectedAmount: Decimal,
        currency: String,
        cadence: Cadence,
        firstSeen: Date,
        lastSeen: Date,
        occurrences: Int,
        dismissed: Bool = false,
        category: TxCategory? = nil,
        account: Account? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.payeePattern = payeePattern
        self.displayName = displayName
        self.expectedAmount = expectedAmount
        self.currency = currency
        self.cadenceRaw = cadence.rawValue
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.occurrences = occurrences
        self.dismissed = dismissed
        self.category = category
        self.account = account
        self.createdAt = createdAt
    }

    enum Cadence: String, Codable, CaseIterable {
        case weekly, monthly, yearly

        var displayName: String {
            switch self { case .weekly: "Weekly"; case .monthly: "Monthly"; case .yearly: "Yearly" }
        }
        /// Approximate days per occurrence; used to estimate monthly cost.
        var days: Double {
            switch self { case .weekly: 7; case .monthly: 30.44; case .yearly: 365.25 }
        }
    }

    var cadence: Cadence {
        get { Cadence(rawValue: cadenceRaw) ?? .monthly }
        set { cadenceRaw = newValue.rawValue }
    }

    /// Estimated cost / income per calendar month, in `currency`.
    var monthlyEstimate: Decimal {
        let perMonth = 30.44 / cadence.days
        return expectedAmount * Decimal(perMonth)
    }
}
