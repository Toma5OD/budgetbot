import Foundation
import SwiftData

/// A user-defined savings target. The user creates one ("Japan trip, €5,000
/// by Dec 2026"), logs contributions over time, and watches a progress ring
/// fill. Distinct from the monthly budget — that's a *spending cap*, this
/// is a *directional goal*.
///
/// SwiftData/CloudKit constraints honoured: every stored property has a
/// default, the to-many relationship is optional, no `@Attribute(.unique)`.
@Model
final class SavingsGoal {
    var id: UUID = UUID()
    var name: String = ""
    var emoji: String = "🎯"
    /// Amount the user is trying to save, in `currency`.
    var targetAmount: Decimal = 0
    var currency: String = "EUR"
    /// Optional. When set, drives the "you need €X / day" projection.
    var deadline: Date?
    var createdAt: Date = Date.now
    /// Set when the goal is achieved (manually marked or hit target).
    /// We don't auto-archive — the user might want to keep it visible.
    var completedAt: Date?
    /// Optional free-text — "for the wedding fund", "split with Alex".
    var note: String?

    @Relationship(deleteRule: .cascade, inverse: \GoalContribution.goal)
    var contributions: [GoalContribution]?

    init(
        id: UUID = UUID(),
        name: String,
        emoji: String = "🎯",
        targetAmount: Decimal,
        currency: String = "EUR",
        deadline: Date? = nil,
        note: String? = nil,
        createdAt: Date = .now,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.targetAmount = targetAmount
        self.currency = currency
        self.deadline = deadline
        self.note = note
        self.createdAt = createdAt
        self.completedAt = completedAt
    }

    /// Non-optional accessor for readability. Use this instead of
    /// `contributions ?? []` at call sites.
    var contributionsList: [GoalContribution] { contributions ?? [] }

    /// Sum of all logged contributions, in `currency`. No FX — contributions
    /// are assumed to be in the goal's currency. The contribution sheet
    /// enforces this at write time.
    var currentAmount: Decimal {
        contributionsList.reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// 0...1 progress. Clamped so an overshoot still renders cleanly.
    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        let cur = NSDecimalNumber(decimal: currentAmount).doubleValue
        let tar = NSDecimalNumber(decimal: targetAmount).doubleValue
        return min(1, max(0, cur / tar))
    }

    /// True once `currentAmount >= targetAmount`, regardless of whether
    /// the user has manually marked it `completedAt`.
    var isHit: Bool { currentAmount >= targetAmount && targetAmount > 0 }

    var remaining: Decimal { max(0, targetAmount - currentAmount) }

    /// `nil` if no deadline set or deadline has passed.
    var daysRemaining: Int? {
        guard let deadline else { return nil }
        let cal = Calendar.current
        let days = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: .now),
                                      to: cal.startOfDay(for: deadline)).day ?? 0
        return max(0, days)
    }

    /// Daily contribution needed to hit the target by the deadline.
    /// `nil` if no deadline or already hit.
    var requiredPerDay: Decimal? {
        guard let days = daysRemaining, days > 0, !isHit else { return nil }
        return remaining / Decimal(days)
    }

    /// Pace heuristic — how close we are to the trajectory needed to hit
    /// the target by the deadline. Computed against `daysSinceCreated`
    /// for the actual rate the user is hitting.
    enum Pace { case ahead, onTrack, behind, impossible, noDeadline }
    var pace: Pace {
        guard let _ = deadline else { return .noDeadline }
        guard let req = requiredPerDay else {
            return isHit ? .ahead : .impossible
        }
        let cal = Calendar.current
        let elapsed = max(1, cal.dateComponents([.day],
                                                from: cal.startOfDay(for: createdAt),
                                                to: cal.startOfDay(for: .now)).day ?? 1)
        let actualPerDay = currentAmount / Decimal(elapsed)
        if actualPerDay >= req { return .ahead }
        if actualPerDay >= req * Decimal(0.75) { return .onTrack }
        return .behind
    }
}

/// A single contribution toward a goal — typically a manual transfer the
/// user logs from the goal sheet. We keep contributions as a separate
/// model (rather than denormalising into `SavingsGoal`) so they're
/// auditable, editable, and can carry their own notes.
@Model
final class GoalContribution {
    var id: UUID = UUID()
    var amount: Decimal = 0
    var date: Date = Date.now
    var note: String?

    @Relationship var goal: SavingsGoal?

    init(
        id: UUID = UUID(),
        amount: Decimal,
        date: Date = .now,
        note: String? = nil,
        goal: SavingsGoal? = nil
    ) {
        self.id = id
        self.amount = amount
        self.date = date
        self.note = note
        self.goal = goal
    }
}
