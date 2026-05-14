import Foundation
import SwiftData
import WidgetKit

/// Computes the current `WidgetSnapshot` from SwiftData state and writes
/// it to the App Group container so the widget extension can render
/// without touching the database. Call after every commit that changes
/// monthly spend and from `.scenePhase` transitions to active.
@MainActor
enum WidgetSnapshotService {

    static func refresh(context: ModelContext, fx: FXService) {
        let profiles = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
        let profile = profiles.first
        let base = profile?.baseCurrency
            ?? profile?.defaultCurrency
            ?? Currencies.localeDefault

        let cal = Calendar.current
        let now = Date()
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let daysSoFar = max(1, cal.component(.day, from: now))

        // Pull only confirmed expense transactions in the current month —
        // smallest predicate that lets the snapshot be cheap to compute.
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate {
                $0.confirmed && $0.amount < 0 && $0.date >= monthStart
            }
        )
        let txs = (try? context.fetch(descriptor)) ?? []

        var totalSpent: Decimal = 0
        var byCategory: [String: (amount: Decimal, emoji: String)] = [:]
        for tx in txs {
            let slices = tx.categorisedSlices(in: base) {
                fx.convert($0, from: $1, to: $2)
            }
            for slice in slices where slice.amount < 0 {
                totalSpent += -slice.amount
                let name = slice.category?.name ?? "Other"
                let emoji = slice.category?.emoji ?? "🧾"
                let prior = byCategory[name]?.amount ?? 0
                byCategory[name] = (prior + -slice.amount, emoji)
            }
        }

        let top = byCategory.max { $0.value.amount < $1.value.amount }
        let snapshot = WidgetSnapshot(
            baseCurrency: base,
            monthSpent: totalSpent,
            monthBudget: profile?.monthlyBudget,
            dailyAverage: totalSpent / Decimal(daysSoFar),
            topCategoryName: top?.key,
            topCategoryEmoji: top?.value.emoji
        )
        WidgetSnapshotStore.write(snapshot)

        // Nudge the widget to refresh now rather than waiting for its
        // next timeline tick. Cheap; iOS coalesces.
        WidgetCenter.shared.reloadAllTimelines()
    }
}
