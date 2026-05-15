import Foundation
import SwiftData

/// Back-links transactions to their `RecurringRule` after the subscription
/// scan has updated the rule catalogue.
///
/// Why this lives in its own service: the existing `SubscriptionDetector`
/// only produces *rule candidates*. It doesn't know about the SwiftData
/// `Transaction` objects — by design, so it's pure and testable. Once the
/// rules exist, we need a second pass that walks the transactions and
/// stamps `recurringRuleID` on each one that fits a rule.
///
/// Same pass propagates `hindsightRating` *within* a series, so:
///   - rating any one Netflix charge instantly rates every Netflix charge,
///     past and future
///   - new charges that the bank pulls in tomorrow inherit the rating
///     from their already-rated siblings the next time the scan runs
@MainActor
enum SeriesLinker {

    /// Tolerance for amount-vs-rule matching. Subscriptions occasionally
    /// fluctuate a euro or two (currency conversion drift, partial
    /// refunds). 5% covers the realistic noise.
    private static let amountTolerance: Decimal = 0.05

    /// Walks `rules` and for each rule finds matching transactions
    /// (same normalised payee, amount within tolerance, expense sign).
    /// Sets `recurringRuleID` and propagates `hindsightRating` from any
    /// already-rated sibling. Returns the number of transactions that
    /// changed so the caller can short-circuit the save when nothing
    /// did.
    @discardableResult
    static func backlink(
        rules: [RecurringRule],
        transactions: [Transaction]
    ) -> Int {
        var mutations = 0

        for rule in rules where !rule.dismissed {
            let key = rule.payeePattern.lowercased()
            let ruleAmount = abs(rule.expectedAmount)
            let lower = ruleAmount * (1 - amountTolerance)
            let upper = ruleAmount * (1 + amountTolerance)

            let matches = transactions.filter { tx in
                guard tx.amount < 0 else { return false }
                let amt = abs(tx.amount)
                guard amt >= lower && amt <= upper else { return false }
                return PayeeNormaliser.key(tx.payee) == key
            }

            guard !matches.isEmpty else { continue }

            // Pick a propagating rating — the most recent non-nil one
            // wins so a user can "correct" the series rating later by
            // rating any single tx in it.
            let propagated: Int? = matches
                .filter { $0.hindsightRating != nil }
                .max(by: { ($0.hindsightRatedAt ?? .distantPast)
                              < ($1.hindsightRatedAt ?? .distantPast) })?
                .hindsightRating

            for tx in matches {
                if tx.recurringRuleID != rule.id {
                    tx.recurringRuleID = rule.id
                    mutations += 1
                }
                if let propagated, tx.hindsightRating == nil {
                    tx.hindsightRating = propagated
                    tx.hindsightRatedAt = .now
                    mutations += 1
                }
            }
        }
        return mutations
    }

    /// Called when the user rates a single transaction. If the
    /// transaction is part of a recurring series, copy the rating to
    /// every other unrated tx in the same series. Returns the count
    /// of siblings that were updated, so the UI can surface "Also
    /// rated 13 other Netflix charges."
    @discardableResult
    static func propagate(
        ratingFrom tx: Transaction,
        in context: ModelContext
    ) -> Int {
        guard let ruleID = tx.recurringRuleID,
              let rating = tx.hindsightRating else { return 0 }

        // SwiftData's #Predicate macro can't compare two persistent-
        // property key paths against each other, so we fetch the whole
        // series and filter `id != tx.id` in Swift. The series size is
        // small in practice (an individual subscription).
        let txID = tx.id
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate {
                $0.recurringRuleID == ruleID && $0.hindsightRating == nil
            }
        )
        let allSiblings = (try? context.fetch(descriptor)) ?? []
        let siblings = allSiblings.filter { $0.id != txID }
        let stamp = tx.hindsightRatedAt ?? .now
        for sibling in siblings {
            sibling.hindsightRating = rating
            sibling.hindsightRatedAt = stamp
        }
        return siblings.count
    }

    /// Counts how many *other* transactions would be affected if the
    /// supplied tx is rated. Used by the UI to show "Will rate all N
    /// Netflix charges" *before* the user taps a star.
    static func seriesSize(
        for tx: Transaction,
        in context: ModelContext
    ) -> Int {
        guard let ruleID = tx.recurringRuleID else { return 0 }
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.recurringRuleID == ruleID }
        )
        let total = (try? context.fetchCount(descriptor)) ?? 0
        return max(0, total - 1)  // exclude the tx itself
    }
}
