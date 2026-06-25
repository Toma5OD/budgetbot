import Foundation
import SwiftData

/// One-off retroactive categorisation for transactions that predate the
/// needs-vs-wants fix — Quick Add rows and bank imports that were left
/// uncategorised. Assigns a best-effort category from the merchant so
/// historical data flows into needs-vs-wants and the analytics.
///
/// Safe by construction: it only *fills* an empty category, never
/// overwrites one the user set, never touches income or already-split
/// transactions, and skips merchants it doesn't recognise (those stay
/// uncategorised, which is honest).
enum CategoryBackfill {

    private static let doneKey = "BudgetBot.categoryBackfill.v1.done"

    /// Runs the backfill exactly once per install.
    @MainActor
    static func runOnceIfNeeded(_ context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return }
        _ = run(in: context)
        UserDefaults.standard.set(true, forKey: doneKey)
    }

    /// Runs the backfill and returns how many transactions it categorised.
    /// Safe to re-run — it only acts on still-uncategorised rows.
    @MainActor
    @discardableResult
    static func run(in context: ModelContext) -> Int {
        let categories = (try? context.fetch(FetchDescriptor<TxCategory>())) ?? []
        var byName: [String: TxCategory] = [:]
        for c in categories { byName[c.name.lowercased()] = c }

        let txs = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        var fixed = 0
        for tx in txs {
            guard tx.amount < 0,                 // expenses only
                  tx.category == nil,            // don't overwrite the user
                  tx.splitItems.isEmpty          // itemised rows classify per split
            else { continue }
            guard let name = MerchantCategory.resolve(tx.payee),
                  let category = byName[name.lowercased()]
            else { continue }
            tx.category = category
            fixed += 1
        }
        if fixed > 0 { try? context.save() }
        return fixed
    }
}
