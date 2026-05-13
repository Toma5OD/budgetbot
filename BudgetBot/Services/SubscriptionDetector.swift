import Foundation

/// Spots recurring payments in transaction history. Pure logic — pass it
/// snapshots, get candidates back. Doesn't touch SwiftData itself; callers
/// upsert `RecurringRule` rows.
struct SubscriptionDetector {

    /// Minimal data each transaction needs to expose. Built once from
    /// SwiftData and reused by detection.
    struct Snapshot: Hashable {
        let id: UUID
        let date: Date
        let payee: String
        let amount: Decimal      // signed; expenses negative
        let currency: String
        let categoryName: String?
    }

    /// Output candidate. Stable per (payeeKey, cadence, currency).
    struct Candidate: Identifiable, Hashable {
        let id: String           // payeeKey + cadence — stable across runs
        let payeeKey: String     // normalised
        let displayName: String  // payee as last seen on a transaction
        let cadence: RecurringRule.Cadence
        let expectedAmount: Decimal
        let currency: String
        let firstSeen: Date
        let lastSeen: Date
        let occurrences: Int
        let category: String?    // last category seen
        let confidence: Double   // 0..1
    }

    var minOccurrences: Int = 3
    var amountToleranceFraction: Double = 0.2   // 20% amount variance OK
    var monthlyDaysRange: ClosedRange<Double> = 25...35
    var weeklyDaysRange:  ClosedRange<Double> = 5...9
    var yearlyDaysRange:  ClosedRange<Double> = 350...380

    /// Returns one candidate per recurring (payee, cadence, currency) group.
    func detect(in snapshots: [Snapshot]) -> [Candidate] {
        // Group expenses by (normalised payee, currency, sign-bucket).
        let buckets = Dictionary(grouping: snapshots.filter { $0.amount < 0 }) {
            Key(payee: normalise($0.payee), currency: $0.currency)
        }

        var out: [Candidate] = []
        for (key, group) in buckets {
            guard group.count >= minOccurrences else { continue }
            let sorted = group.sorted { $0.date < $1.date }

            // Amount stability: discard if amounts vary too much.
            let amounts = sorted.map { NSDecimalNumber(decimal: -$0.amount).doubleValue }
            let mean = amounts.reduce(0, +) / Double(amounts.count)
            guard mean > 0 else { continue }
            let withinTolerance = amounts.allSatisfy { a in
                abs(a - mean) / mean <= amountToleranceFraction
            }
            guard withinTolerance else { continue }

            // Intervals between consecutive occurrences (in days).
            let intervals: [Double] = zip(sorted.dropFirst(), sorted).map { later, earlier in
                later.date.timeIntervalSince(earlier.date) / 86_400
            }
            guard !intervals.isEmpty else { continue }
            let avgInterval = intervals.reduce(0, +) / Double(intervals.count)

            let cadence: RecurringRule.Cadence
            switch avgInterval {
            case weeklyDaysRange:  cadence = .weekly
            case monthlyDaysRange: cadence = .monthly
            case yearlyDaysRange:  cadence = .yearly
            default: continue
            }

            // Confidence: more occurrences + tighter amount variance = higher.
            let stddev = sqrt(amounts.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(amounts.count))
            let amountStability = max(0, 1.0 - (stddev / mean) / amountToleranceFraction)
            let countBonus = min(1.0, Double(group.count) / 6.0)
            let confidence = max(0.05, min(1.0, 0.5 * amountStability + 0.5 * countBonus))

            let lastSeen = sorted.last!
            out.append(Candidate(
                id: "\(key.payee)__\(cadence.rawValue)__\(key.currency)",
                payeeKey: key.payee,
                displayName: lastSeen.payee,
                cadence: cadence,
                expectedAmount: Decimal(-mean),    // signed, negative for expense
                currency: key.currency,
                firstSeen: sorted.first!.date,
                lastSeen: lastSeen.date,
                occurrences: group.count,
                category: lastSeen.categoryName,
                confidence: confidence
            ))
        }
        return out.sorted { $0.confidence > $1.confidence }
    }

    // MARK: - Helpers

    static func normalise(_ s: String) -> String {
        s.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map { String($0) }
            .joined()
    }

    func normalise(_ s: String) -> String { Self.normalise(s) }

    private struct Key: Hashable {
        let payee: String
        let currency: String
    }
}
