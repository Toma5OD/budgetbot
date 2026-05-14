import WidgetKit
import SwiftUI

// BudgetBot Home Screen widget. Reads the JSON snapshot the main app
// writes into the App Group container — no SwiftData dependency in the
// widget extension, so the widget compiles fast and stays stable across
// SwiftData schema rewrites.

@main
struct BudgetBotWidgetBundle: WidgetBundle {
    var body: some Widget {
        MonthSpendWidget()
    }
}

// MARK: - Timeline

/// Single entry that holds whatever the snapshot file had at refresh
/// time. WidgetKit calls the provider periodically + when the main app
/// calls `WidgetCenter.shared.reloadAllTimelines()`.
struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: WidgetSnapshotStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: WidgetSnapshotStore.read())
        // Refresh every 30 min as a fallback in case the main app hasn't
        // pinged us via `reloadAllTimelines()`.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Widget

struct MonthSpendWidget: Widget {
    let kind: String = "MonthSpendWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            MonthSpendWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [Color(red: 0.07, green: 0.07, blue: 0.15),
                                 Color(red: 0.02, green: 0.02, blue: 0.08)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("This month")
        .description("How much you've spent this month, with budget progress.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - View

struct MonthSpendWidgetView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium: medium
        default:            small
        }
    }

    // MARK: small

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("This month")
                .font(.caption2.bold())
                .foregroundStyle(.white.opacity(0.75))
                .tracking(0.5)
            Text(formattedAmount(snapshot.monthSpent))
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let budget = snapshot.monthBudget, budget > 0 {
                budgetRow(spent: snapshot.monthSpent, budget: budget)
            }
            Spacer(minLength: 0)
            if let cat = snapshot.topCategoryName,
               let emoji = snapshot.topCategoryEmoji {
                HStack(spacing: 4) {
                    Text(emoji).font(.caption)
                    Text(cat)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
        }
        .padding(2)
    }

    // MARK: medium

    private var medium: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("This month")
                    .font(.caption.bold())
                    .tracking(0.5)
                    .foregroundStyle(.white.opacity(0.75))
                Text(formattedAmount(snapshot.monthSpent))
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if let budget = snapshot.monthBudget, budget > 0 {
                    budgetRow(spent: snapshot.monthSpent, budget: budget)
                }
                Spacer(minLength: 0)
                Text("Avg \(formattedAmount(snapshot.dailyAverage))/day")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            if let cat = snapshot.topCategoryName,
               let emoji = snapshot.topCategoryEmoji {
                VStack(spacing: 4) {
                    Text(emoji).font(.system(size: 30))
                    Text("Top: \(cat)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                .frame(width: 90)
            }
        }
    }

    // MARK: helpers

    @ViewBuilder
    private func budgetRow(spent: Decimal, budget: Decimal) -> some View {
        let pct = NSDecimalNumber(decimal: spent).doubleValue
                / max(0.01, NSDecimalNumber(decimal: budget).doubleValue)
        let clamped = min(max(pct, 0), 1)
        let over = pct > 1.0
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.18))
                    Capsule()
                        .fill(over ? Color.red : (pct > 0.75 ? Color.orange : Color.green))
                        .frame(width: geo.size.width * clamped)
                }
            }
            .frame(height: 5)
            Text(over
                 ? "\(Int((pct - 1.0) * 100))% over"
                 : "\(Int((1 - pct) * 100))% left")
                .font(.caption2.bold().monospacedDigit())
                .foregroundStyle(over ? Color.red : .white.opacity(0.85))
        }
    }

    private func formattedAmount(_ d: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = snapshot.baseCurrency
        f.maximumFractionDigits = 0
        return f.string(from: d as NSDecimalNumber) ?? "\(d)"
    }
}
