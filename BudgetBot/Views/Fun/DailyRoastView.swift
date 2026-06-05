import SwiftUI
import SwiftData

/// Today's harsh-jokey review of the user's recent spend and save
/// behaviour. Pulls a 7-day slice from SwiftData, snapshots it into
/// `DailyRoast.Input`, and renders the resulting `RoastLine`s.
struct DailyRoastView: View {
    @Environment(ThemeManager.self) private var theme

    @Query(sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]

    @Query private var goals: [SavingsGoal]
    @Query private var subscriptions: [RecurringRule]

    /// Frozen at view creation so the roast is the same every time the
    /// user opens it during the day. Tapping "Roll again" advances it.
    @State private var now: Date = .now

    private var input: DailyRoast.Input {
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -7, to: now) ?? now
        let today = cal.startOfDay(for: now)
        return DailyRoast.Input(
            now: now,
            recentTransactions: transactions
                .filter { $0.confirmed && $0.date > cutoff }
                .map { tx in
                    DailyRoast.TxSnapshot(
                        payee: tx.payee,
                        amount: tx.amount,
                        date: tx.date,
                        categoryName: tx.category?.name
                    )
                },
            activeGoals: goals
                .filter { g in
                    guard let completed = g.completedAt else { return true }
                    return cal.startOfDay(for: completed) == today
                }
                .map { goal in
                    DailyRoast.GoalSnapshot(
                        isHit: goal.isHit,
                        pace: goal.pace,
                        completedAt: goal.completedAt
                    )
                },
            subscriptionCount: subscriptions.filter { !$0.dismissed }.count
        )
    }

    private var lines: [RoastLine] { DailyRoast.generate(input: input) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                ForEach(lines, id: \.self) { line in
                    lineCard(line)
                }
                footer
            }
            .padding(16)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Daily Roast")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Pieces

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(now.formatted(date: .complete, time: .omitted))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Today's roast")
                .font(.title.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func lineCard(_ line: RoastLine) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon(line.tone))
                .font(.title3)
                .foregroundStyle(color(line.tone))
                .frame(width: 36, height: 36)
                .background(color(line.tone).opacity(0.15), in: Circle())
            Text(line.text)
                .font(.body)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(16)
        .themedCard()
    }

    private var footer: some View {
        Text("Generated from your last week of spending and saving. No punches pulled.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    private func icon(_ tone: RoastLine.Tone) -> String {
        switch tone {
        case .roast:   return "flame.fill"
        case .praise:  return "sparkles"
        case .neutral: return "ellipsis.circle.fill"
        }
    }

    private func color(_ tone: RoastLine.Tone) -> Color {
        switch tone {
        case .roast:   return theme.current.expenseColor
        case .praise:  return theme.current.incomeColor
        case .neutral: return .gray
        }
    }
}
