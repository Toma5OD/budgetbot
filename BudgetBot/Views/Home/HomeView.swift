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
    @Query(filter: #Predicate<Transaction> { $0.confirmed && $0.isRegret },
           sort: \Transaction.date, order: .reverse)
    private var regrets: [Transaction]
    @Query(
        filter: #Predicate<Transaction> {
            $0.confirmed && $0.hindsightRating == nil && $0.amount < 0
        },
        sort: \Transaction.date, order: .reverse
    )
    private var unratedForHindsight: [Transaction]
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
                    if unratedForHindsight.count >= 3 { hindsightBanner }
                    if !regrets.isEmpty { regretsBanner }
                    accountsStrip
                    if !rules.isEmpty { subscriptionsTeaser }
                    recentActivity
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
                case .hallOfShame:      HallOfShameView()
                case .hindsightReview:  HindsightReviewView()
                }
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

    // MARK: - Hindsight banner

    private var hindsightBanner: some View {
        NavigationLink(value: HomeRoute.hindsightReview) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [.yellow, .orange.opacity(0.75)],
                            startPoint: .top, endPoint: .bottom))
                        .frame(width: 44, height: 44)
                    Image(systemName: "star.leadinghalf.filled")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rate \(unratedForHindsight.count) purchases")
                        .font(.subheadline.bold())
                    Text("Quick game — tap or swipe stars. Tightens your analytics.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(14)
            .themedCard()
            .padding(.horizontal, 16)
        }
        .buttonStyle(.pressable)
    }

    // MARK: - Regrets banner

    private var regretsBanner: some View {
        let total = regrets.reduce(Decimal(0)) { acc, tx in
            acc + (-tx.amountInBase(base) { fx.convert($0, from: $1, to: $2) })
        }
        return NavigationLink(value: HomeRoute.hallOfShame) {
            HStack(spacing: 14) {
                Text(regrets.first?.regretEmoji ?? "🤡")
                    .font(.system(size: 36))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hall of Shame")
                        .font(.subheadline.bold())
                    Text("\(regrets.count) silly purchase\(regrets.count == 1 ? "" : "s") · \(CurrencyFormatter.string(for: total, currency: base))")
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
                Button {
                    selectedTab = 3   // Analytics tab
                } label: {
                    Text("All")
                        .font(.caption.bold())
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 20)

            let totalMonthly = rules.reduce(Decimal(0)) { acc, r in
                acc + (-fx.convert(r.monthlyEstimate, from: r.currency, to: base))
            }
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
            .onTapGesture { selectedTab = 3 }
        }
    }

    // MARK: - Recent activity

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent activity").font(.subheadline.bold())
                Spacer()
                Button {
                    selectedTab = 1   // Activity tab
                } label: {
                    Text("All")
                        .font(.caption.bold())
                        .foregroundStyle(.tint)
                }
                .accessibilityIdentifier("home.allActivity")
            }
            .padding(.horizontal, 20)

            if transactions.isEmpty {
                emptyRecent
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(transactions.prefix(5))) { tx in
                        NavigationLink(value: tx) {
                            TransactionRow(tx: tx).padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        if tx.id != transactions.prefix(5).last?.id {
                            RowDivider()
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .themedCard()
                .padding(.horizontal, 16)
            }
        }
    }

    private var emptyRecent: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No transactions yet.")
                .font(.callout.bold())
            Text("Tap **Capture** to add your first receipt.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .themedCard()
        .padding(.horizontal, 16)
    }
}

/// Typed nav destinations off the Home stack (anything that isn't a
/// raw model). Add cases here when adding new pushable screens.
enum HomeRoute: Hashable {
    case hallOfShame
    case hindsightReview
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
