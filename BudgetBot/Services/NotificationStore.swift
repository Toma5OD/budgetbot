import Foundation
import SwiftData

/// A computed (not pushed-to-APNs) in-app notification. Surfaces things the
/// user would want flagged: pending share-extension items, newly-detected
/// subscriptions, budget threshold crossings, fresh AI recommendations.
struct AppNotification: Identifiable, Hashable {
    let id: String
    let date: Date
    let title: String
    let body: String
    let icon: String
    let kind: Kind

    enum Kind: Hashable {
        case pendingCapture(count: Int)
        case subscriptionDetected(payee: String)
        case budgetThreshold(percent: Int)
        case aiRecommendation(id: UUID)

        var tintName: String {
            switch self {
            case .pendingCapture:        "blue"
            case .subscriptionDetected:  "purple"
            case .budgetThreshold:       "orange"
            case .aiRecommendation:      "green"
            }
        }
    }

    /// Helper: a stable identifier so we can compute unread-vs-seen.
    var seenKey: String { id }
}

@Observable
@MainActor
final class NotificationStore {
    /// UNIX epoch of the last time the user opened the notifications center.
    /// Notifications newer than this are "unread".
    @ObservationIgnored private let lastSeenKey = "notifications.lastSeenAt"

    private(set) var items: [AppNotification] = []
    private(set) var unreadCount: Int = 0

    var lastSeen: Date {
        get { Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: lastSeenKey)) }
        set { UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: lastSeenKey) }
    }

    /// Rebuild from current SwiftData state + pending captures. Called by
    /// the toolbar whenever the app enters foreground or a relevant query
    /// changes.
    func rebuild(
        context: ModelContext,
        baseCurrency: String,
        monthlyBudget: Decimal?
    ) {
        var out: [AppNotification] = []

        // 1) Pending share-extension captures
        let pending = PendingCaptureStore.pending()
        if !pending.isEmpty {
            let latest = pending.last?.createdAt ?? .now
            out.append(AppNotification(
                id: "pending.\(pending.count)",
                date: latest,
                title: "\(pending.count) item\(pending.count == 1 ? "" : "s") waiting",
                body: "Shared from another app. Tap Capture to import.",
                icon: "tray.and.arrow.down.fill",
                kind: .pendingCapture(count: pending.count)
            ))
        }

        // 2) Recently detected subscriptions
        let rulesDesc = FetchDescriptor<RecurringRule>(
            predicate: #Predicate<RecurringRule> { !$0.dismissed },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let rules = (try? context.fetch(rulesDesc)) ?? []
        let recentRules = rules.prefix(3)
        for r in recentRules {
            out.append(AppNotification(
                id: "rule.\(r.id.uuidString)",
                date: r.createdAt,
                title: "Subscription detected",
                body: "\(r.displayName) (~\(formatted(r.expectedAmount, currency: r.currency)) \(r.cadence.displayName.lowercased()))",
                icon: "arrow.triangle.2.circlepath.circle.fill",
                kind: .subscriptionDetected(payee: r.displayName)
            ))
        }

        // 3) Budget threshold crossings
        if let budget = monthlyBudget, budget > 0 {
            let startOfMonth = Calendar.current.date(from:
                Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
            let txDesc = FetchDescriptor<Transaction>(
                predicate: #Predicate<Transaction> { $0.confirmed && $0.date >= startOfMonth },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            let txs = (try? context.fetch(txDesc)) ?? []
            let spent: Decimal = txs.filter { $0.amount < 0 }.reduce(0) { $0 + (-$1.amount) }
            let pct = NSDecimalNumber(decimal: spent).doubleValue
                / max(0.01, NSDecimalNumber(decimal: budget).doubleValue)
            let percentInt = Int((pct * 100).rounded())
            if pct >= 1.0 {
                out.append(AppNotification(
                    id: "budget.over",
                    date: .now,
                    title: "Over budget for this month",
                    body: "You've spent \(formatted(spent, currency: baseCurrency)) of \(formatted(budget, currency: baseCurrency)) — \(percentInt - 100)% over.",
                    icon: "exclamationmark.triangle.fill",
                    kind: .budgetThreshold(percent: percentInt)
                ))
            } else if pct >= 0.8 {
                out.append(AppNotification(
                    id: "budget.80",
                    date: .now,
                    title: "Approaching your budget",
                    body: "You're at \(percentInt)% of your monthly budget. \(formatted(budget - spent, currency: baseCurrency)) left.",
                    icon: "speedometer",
                    kind: .budgetThreshold(percent: percentInt)
                ))
            }
        }

        // 4) Fresh AI recommendations
        let recsDesc = FetchDescriptor<AIRecommendation>(
            predicate: #Predicate<AIRecommendation> { !$0.dismissed },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let recs = (try? context.fetch(recsDesc)) ?? []
        for r in recs.prefix(3) {
            out.append(AppNotification(
                id: "rec.\(r.id.uuidString)",
                date: r.createdAt,
                title: r.title,
                body: r.body,
                icon: r.kind == .silly ? "exclamationmark.bubble.fill"
                    : r.kind == .savings ? "leaf.fill" : "lightbulb.fill",
                kind: .aiRecommendation(id: r.id)
            ))
        }

        items = out.sorted { $0.date > $1.date }

        let cutoff = lastSeen
        unreadCount = items.filter { $0.date > cutoff }.count
    }

    func markAllRead() {
        lastSeen = .now
        unreadCount = 0
    }

    // MARK: - Helpers

    private func formatted(_ d: Decimal, currency: String) -> String {
        CurrencyFormatter.string(for: d, currency: currency)
    }
}
