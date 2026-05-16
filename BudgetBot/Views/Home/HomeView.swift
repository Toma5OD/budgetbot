import SwiftUI
import SwiftData

/// The first thing a budget-app user wants to see: how are they doing this
/// month, what just happened, where are their balances, and what's the next
/// thing they should act on. Capture, Activity, Analytics, Ask remain
/// dedicated tabs — this is the at-a-glance home.
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(FXService.self) private var fx
    @Environment(ThemeManager.self) private var theme
    @Environment(\.scenePhase) private var scenePhase

    @Query(filter: #Predicate<Transaction> { $0.confirmed }, sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]
    @Query(sort: \SavingsGoal.createdAt, order: .reverse) private var goals: [SavingsGoal]
    @Query(filter: #Predicate<Account> { !$0.archived }, sort: \Account.createdAt)
    private var accounts: [Account]
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @Query(filter: #Predicate<RecurringRule> { !$0.dismissed },
           sort: \RecurringRule.lastSeen, order: .reverse)
    private var rules: [RecurringRule]

    @State private var showAddAccount = false
    @Binding var selectedTab: Int

    private var base: String {
        profiles.first?.baseCurrency ?? Currencies.localeDefault
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    greeting
                    monthHero
                    quickActions
                    if needVsWantSplit.total > 0 { needVsWantCard }
                    if hasRecentSpend { monthlyTrendCard }
                    if !goals.isEmpty { goalsStrip }
                    accountsStrip
                    if !rules.isEmpty { subscriptionsTeaser }
                }
                .padding(.bottom, 28)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
            .appHeaderToolbar()
            .navigationDestination(for: Transaction.self) { tx in
                TransactionDetailView(tx: tx)
            }
            .navigationDestination(for: Account.self) { a in
                AccountDetailView(account: a)
            }
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .hindsightReview:  HindsightReviewView()
                case .savingsGoals:     SavingsGoalsView()
                case .subscriptions:    SubscriptionsView()
                }
            }
            .navigationDestination(for: SavingsGoal.self) { goal in
                GoalDetailView(goal: goal)
            }
            .sheet(isPresented: $showAddAccount) {
                AddAccountView()
            }
        }
    }

    // MARK: - Greeting

    private var greeting: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(timeGreeting)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(firstName)
                    .font(theme.current.headingFont(.largeTitle))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private var timeGreeting: String {
        let h = Calendar.current.component(.hour, from: .now)
        switch h {
        case 5..<12:  return "Good morning,"
        case 12..<17: return "Good afternoon,"
        case 17..<22: return "Good evening,"
        default:      return "Good night,"
        }
    }

    private var firstName: String {
        if let full = profiles.first?.displayName, !full.isEmpty {
            return full.split(separator: " ").first.map(String.init) ?? full
        }
        return "there"
    }

    // MARK: - Month hero

    private var monthHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("This month")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .tracking(0.6)
                .padding(.horizontal, 4)

            HStack(alignment: .firstTextBaseline) {
                Text(CurrencyFormatter.string(for: monthSpent, currency: base))
                    .font(.system(size: 38, weight: .bold, design: theme.current.numericDesign))
                    .foregroundStyle(theme.current.expenseColor)
                Spacer()
                if let last = transactions.first {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Last spent")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(last.date, style: .relative)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let budget = profiles.first?.monthlyBudget, budget > 0 {
                let pct = NSDecimalNumber(decimal: monthSpent).doubleValue
                    / max(0.01, NSDecimalNumber(decimal: budget).doubleValue)
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: min(pct, 1.0))
                        .tint(pct < 0.75 ? theme.current.incomeColor :
                              (pct < 1.0 ? .orange : theme.current.expenseColor))
                    HStack {
                        Text(pct > 1.0
                             ? "\(Int((pct - 1.0) * 100))% over budget"
                             : "\(Int((1 - pct) * 100))% remaining")
                        Spacer()
                        Text("Budget \(CurrencyFormatter.string(for: budget, currency: base))")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text("Set a monthly budget in Settings to track progress here.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .themedCard()
        .padding(.horizontal, 16)
    }

    private var monthSpent: Decimal {
        let startOfMonth = Calendar.current.date(from:
            Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
        return transactions
            .filter { $0.amount < 0 && $0.date >= startOfMonth }
            .reduce(Decimal(0)) { acc, tx in
                acc + (-tx.amountInBase(base) { fx.convert($0, from: $1, to: $2) })
            }
    }

    // MARK: - Quick actions

    private var quickActions: some View {
        HStack(spacing: 10) {
            quickActionButton(
                title: "Capture",
                subtitle: "Receipt or photo",
                icon: "camera.viewfinder",
                tint: theme.current.tint
            ) {
                selectedTab = 2   // Capture tab index in MainTabView
            }
            quickActionButton(
                title: "Ask",
                subtitle: "About your money",
                icon: "sparkles",
                tint: .purple
            ) {
                selectedTab = 4   // Ask tab index
            }
            NavigationLink(value: HomeRoute.hindsightReview) {
                quickActionLabel(
                    title: "Rate",
                    subtitle: "Past purchases",
                    icon: "star.leadinghalf.filled",
                    tint: .orange
                )
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func quickActionLabel(title: String, subtitle: String,
                                  icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
            Text(title)
                .font(.subheadline.bold())
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .themedCard()
    }

    @ViewBuilder
    private func quickActionButton(title: String, subtitle: String, icon: String,
                                    tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.subheadline.bold())
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .themedCard()
        }
        .buttonStyle(.pressable)
    }

    // MARK: - Goals strip

    private var goalsStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                NavigationLink(value: HomeRoute.savingsGoals) {
                    HStack(spacing: 4) {
                        Text("Goals").font(.subheadline.bold())
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Text("\(goals.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(goals.prefix(6)) { goal in
                        NavigationLink(value: goal) {
                            GoalTile(goal: goal, theme: theme.current)
                        }
                        .buttonStyle(.pressable)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Needs vs wants

    /// This-month split of essential vs discretionary spend. A simple
    /// two-segment bar — `discretionary` and `regret` from the metric
    /// are folded together into "Wants" so the Home version stays
    /// glanceable (the full three-way breakdown lives in Analytics).
    private var needVsWantCard: some View {
        let split = needVsWantSplit
        let needs = split.necessary
        let wants = split.discretionary + split.regret
        let total = needs + wants
        let needsFrac = total > 0
            ? NSDecimalNumber(decimal: needs).doubleValue
                / NSDecimalNumber(decimal: total).doubleValue
            : 0
        let needsPct = Int((needsFrac * 100).rounded())

        return VStack(alignment: .leading, spacing: 12) {
            Text("Needs vs wants · this month")
                .font(.caption.bold()).tracking(0.5)
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                HStack(spacing: 3) {
                    Capsule().fill(theme.current.tint)
                        .frame(width: max(0, geo.size.width * needsFrac - 1.5))
                    Capsule().fill(theme.current.expenseColor)
                        .frame(width: max(0, geo.size.width * (1 - needsFrac) - 1.5))
                }
            }
            .frame(height: 12)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Circle().fill(theme.current.tint).frame(width: 7, height: 7)
                        Text("Needs").font(.caption2).foregroundStyle(.secondary)
                    }
                    Text("\(CurrencyFormatter.string(for: needs, currency: base)) · \(needsPct)%")
                        .font(.callout.bold().monospacedDigit())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(spacing: 5) {
                        Text("Wants").font(.caption2).foregroundStyle(.secondary)
                        Circle().fill(theme.current.expenseColor).frame(width: 7, height: 7)
                    }
                    Text("\(CurrencyFormatter.string(for: wants, currency: base)) · \(100 - needsPct)%")
                        .font(.callout.bold().monospacedDigit())
                }
            }
        }
        .padding(16)
        .themedCard()
        .padding(.horizontal, 16)
    }

    // MARK: - Monthly trend

    /// Last six months of total spend as a compact bar strip, current
    /// month highlighted, with the active-month average alongside.
    private var monthlyTrendCard: some View {
        let bars = monthlyBars
        let maxSpend = max(bars.map(\.spend).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("6-month spend")
                    .font(.caption.bold()).tracking(0.5)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("avg \(CurrencyFormatter.string(for: monthlyAverage, currency: base))")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(bars) { bar in
                    VStack(spacing: 6) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(bar.isCurrent
                                  ? AnyShapeStyle(LinearGradient(
                                      colors: [theme.current.expenseColor,
                                               theme.current.expenseColor.opacity(0.6)],
                                      startPoint: .top, endPoint: .bottom))
                                  : AnyShapeStyle(theme.current.expenseColor.opacity(0.25)))
                            .frame(height: barHeight(for: bar.spend, max: maxSpend))
                        Text(bar.label)
                            .font(.caption2)
                            .foregroundStyle(bar.isCurrent ? Color.primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 96)
        }
        .padding(16)
        .themedCard()
        .padding(.horizontal, 16)
    }

    private func barHeight(for spend: Decimal, max maxSpend: Decimal) -> CGFloat {
        let frac = NSDecimalNumber(decimal: spend).doubleValue
            / NSDecimalNumber(decimal: maxSpend).doubleValue
        // Floor so even a zero-spend month keeps a visible sliver.
        return CGFloat(max(0.05, min(1, frac))) * 72
    }

    // MARK: - Accounts strip

    private var accountsStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Accounts")
                    .font(.subheadline.bold())
                Spacer()
                Button { showAddAccount = true } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.tint)
                }
                .accessibilityIdentifier("home.addAccount")
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(accounts) { a in
                        NavigationLink(value: a) {
                            AccountTile(account: a, base: base, fx: fx, theme: theme.current)
                        }
                        .buttonStyle(.pressable)
                    }
                    addAccountTile
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var addAccountTile: some View {
        Button { showAddAccount = true } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.tint)
                Text("Add\naccount")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 150, height: 120)
            .themedCard()
        }
        .buttonStyle(.pressable)
    }

    // MARK: - Subscriptions teaser

    private var subscriptionsTeaser: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Subscriptions", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.subheadline.bold())
                Spacer()
                NavigationLink(value: HomeRoute.subscriptions) {
                    Text("All")
                        .font(.caption.bold())
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)

            let totalMonthly = rules.reduce(Decimal(0)) { acc, r in
                acc + (-fx.convert(r.monthlyEstimate, from: r.currency, to: base))
            }
            NavigationLink(value: HomeRoute.subscriptions) {
                HStack(spacing: 14) {
                    Image(systemName: "repeat.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(rules.count) recurring payment\(rules.count == 1 ? "" : "s")")
                            .font(.subheadline.bold())
                        Text("\(CurrencyFormatter.string(for: totalMonthly, currency: base))/month")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .themedCard()
                .padding(.horizontal, 16)
            }
            .buttonStyle(.pressable)
        }
    }

    // MARK: - Derived data for the new cards

    private func convert(_ amt: Decimal, _ from: String, _ to: String) -> Decimal {
        fx.convert(amt, from: from, to: to)
    }

    /// Confirmed transactions dated within the current calendar month.
    private var thisMonthTransactions: [Transaction] {
        let startOfMonth = Calendar.current.date(from:
            Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
        return transactions.filter { $0.date >= startOfMonth }
    }

    private var needVsWantSplit: AnalyticsMetrics.NeedVsWant {
        AnalyticsMetrics.needVsWant(in: thisMonthTransactions, base: base, convert: convert)
    }

    struct MonthBar: Identifiable {
        let id = UUID()
        let label: String       // "Jan"
        let spend: Decimal      // base-currency expense total
        let isCurrent: Bool
    }

    /// Total expense per month for the trailing six calendar months,
    /// oldest first, current month last.
    private var monthlyBars: [MonthBar] {
        let cal = Calendar.current
        let now = Date()
        let df = DateFormatter(); df.dateFormat = "MMM"
        var bars: [MonthBar] = []
        for offset in stride(from: 5, through: 0, by: -1) {
            guard let anchor = cal.date(byAdding: .month, value: -offset, to: now),
                  let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: anchor)),
                  let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart)
            else { continue }
            let spend = transactions
                .filter { $0.amount < 0 && $0.date >= monthStart && $0.date < monthEnd }
                .reduce(Decimal(0)) { acc, tx in
                    acc + (-tx.amountInBase(base, liveConvert: convert))
                }
            bars.append(MonthBar(label: df.string(from: monthStart),
                                 spend: spend,
                                 isCurrent: offset == 0))
        }
        return bars
    }

    /// Average over months that actually had spend — so a brand-new
    /// install's empty months don't drag the figure to near-zero.
    private var monthlyAverage: Decimal {
        let active = monthlyBars.filter { $0.spend > 0 }
        guard !active.isEmpty else { return 0 }
        return active.reduce(Decimal(0)) { $0 + $1.spend } / Decimal(active.count)
    }

    /// Gate for the trend card — hides it for a brand-new account with
    /// no history rather than showing six flat slivers.
    private var hasRecentSpend: Bool {
        monthlyBars.contains { $0.spend > 0 }
    }
}

/// Typed nav destinations off the Home stack (anything that isn't a
/// raw model). Add cases here when adding new pushable screens.
enum HomeRoute: Hashable {
    case hindsightReview
    case savingsGoals
    case subscriptions
}

// MARK: - Goal tile

private struct GoalTile: View {
    let goal: SavingsGoal
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(goal.emoji).font(.title2)
                Spacer()
                Text("\(Int((goal.progress * 100).rounded()))%")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(goal.name)
                .font(.subheadline.bold())
                .lineLimit(1)
            // Inline progress bar.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.15)).frame(height: 6)
                    Capsule()
                        .fill(LinearGradient(
                            colors: [theme.tint, theme.tint.opacity(0.55)],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * goal.progress, height: 6)
                }
            }
            .frame(height: 6)
            Text(CurrencyFormatter.string(for: goal.currentAmount, currency: goal.currency))
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(.primary)
            Text("of \(CurrencyFormatter.string(for: goal.targetAmount, currency: goal.currency))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 170, height: 140, alignment: .topLeading)
        .themedCard()
    }
}

// MARK: - Account tile

private struct AccountTile: View {
    let account: Account
    let base: String
    let fx: FXService
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: account.kind.systemImage)
                    .foregroundStyle(theme.tint)
                Spacer()
                Text(account.currency)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.tint.opacity(0.15), in: Capsule())
                    .foregroundStyle(theme.tint)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Text(CurrencyFormatter.string(for: account.balance, currency: account.currency))
                    .font(theme.numericFont(.title3, weight: .bold))
                    .foregroundStyle(account.balance >= 0 ? Color.primary : Color.red)
                    .monospacedDigit()
                if account.currency != base {
                    let conv = fx.convert(account.balance, from: account.currency, to: base)
                    Text("≈ \(CurrencyFormatter.string(for: conv, currency: base))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(width: 180, height: 130, alignment: .topLeading)
        .themedCard()
    }
}
