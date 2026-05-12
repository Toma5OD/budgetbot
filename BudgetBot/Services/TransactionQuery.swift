import Foundation

/// Pure, testable transaction querying. The `query_transactions` AI tool calls
/// into this. No `ModelContext`, no SwiftUI — just (snapshot in, filter out).
struct TransactionQuery {

    /// What the AI sees on each row in the result.
    struct Row: Codable, Equatable {
        let date: String          // yyyy-MM-dd
        let payee: String
        let category: String
        let account: String
        let amount: Double        // in original currency, signed
        let currency: String
        let amount_in_base: Double?
        let base_currency: String?
    }

    /// What the AI passes in.
    struct Args: Codable, Equatable {
        var start_date: String?         // yyyy-MM-dd inclusive
        var end_date: String?           // yyyy-MM-dd inclusive
        var payee_contains: String?
        var category: String?
        var min_amount: Double?         // absolute value
        var max_amount: Double?         // absolute value
        var sign: String?               // "positive" | "negative"
        var limit: Int?                 // default 100, max 200
    }

    /// Snapshot of one transaction we can filter without touching SwiftData.
    struct Snapshot {
        let date: Date
        let payee: String
        let category: String
        let account: String
        let amount: Decimal
        let currency: String
        let amountInBase: Decimal
        let baseCurrency: String
    }

    private let iso: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale   = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    func execute(args: Args, against snapshots: [Snapshot]) -> [Row] {
        let limit = max(1, min(args.limit ?? 100, 200))

        let start = args.start_date.flatMap { iso.date(from: $0) }
        let end   = args.end_date.flatMap { iso.date(from: $0) }
        let payeeNeedle = args.payee_contains?.lowercased()
        let categoryNeedle = args.category?.lowercased()
        let minAbs = args.min_amount
        let maxAbs = args.max_amount
        let sign = args.sign?.lowercased()

        return snapshots
            .filter { tx in
                if let s = start, tx.date < s { return false }
                if let e = end {
                    let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: e) ?? e
                    if tx.date >= endOfDay { return false }
                }
                if let p = payeeNeedle, !tx.payee.lowercased().contains(p) { return false }
                if let c = categoryNeedle, !tx.category.lowercased().contains(c) { return false }
                let abs = NSDecimalNumber(decimal: tx.amount < 0 ? -tx.amount : tx.amount).doubleValue
                if let mi = minAbs, abs < mi { return false }
                if let ma = maxAbs, abs > ma { return false }
                if let s = sign {
                    if s == "positive" && tx.amount <= 0 { return false }
                    if s == "negative" && tx.amount >= 0 { return false }
                }
                return true
            }
            .sorted { $0.date > $1.date }
            .prefix(limit)
            .map { tx in
                Row(
                    date: iso.string(from: tx.date),
                    payee: tx.payee,
                    category: tx.category,
                    account: tx.account,
                    amount: NSDecimalNumber(decimal: tx.amount).doubleValue,
                    currency: tx.currency,
                    amount_in_base: tx.currency == tx.baseCurrency ? nil : NSDecimalNumber(decimal: tx.amountInBase).doubleValue,
                    base_currency: tx.currency == tx.baseCurrency ? nil : tx.baseCurrency
                )
            }
    }
}
