import SwiftUI
import SwiftData

/// User profile. Hero header with the avatar over a tinted gradient, inline
/// name editing, stat cards, and an account summary. The card design language
/// matches Settings so the two screens feel like siblings.
struct ProfileView: View {
    @Environment(\.modelContext) private var context
    @Environment(FXService.self) private var fx
    @Environment(ThemeManager.self) private var theme
    @Query(filter: #Predicate<Transaction> { $0.confirmed }) private var transactions: [Transaction]
    @Query(filter: #Predicate<Account> { !$0.archived }) private var accounts: [Account]
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    @State private var editingName = false
    @State private var nameDraft = ""

    private var profile: UserProfile? { profiles.first }

    private var base: String {
        profile?.baseCurrency ?? profile?.defaultCurrency ?? Currencies.localeDefault
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                hero
                statGrid
                if let budget = profile?.monthlyBudget, budget > 0 {
                    budgetCard(budget: budget)
                }
                accountsSection
            }
            .padding(.vertical, 8)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    nameDraft = profile?.displayName ?? ""
                    editingName = true
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel("Edit name")
            }
        }
        .alert("Display name", isPresented: $editingName) {
            TextField("Name", text: $nameDraft)
            Button("Save") {
                profile?.displayName = nameDraft.trimmingCharacters(in: .whitespaces).isEmpty
                    ? nil
                    : nameDraft.trimmingCharacters(in: .whitespaces)
                try? context.save()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 14) {
            ZStack {
                // Glow halo behind avatar
                Circle()
                    .fill(theme.current.tint.opacity(0.18))
                    .frame(width: 180, height: 180)
                    .blur(radius: 16)
                AvatarCircle(initials: initials, size: 96, tint: theme.current.tint)
            }
            .padding(.top, 8)

            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Text(profile?.displayName ?? "Set your name")
                        .font(.title2.bold())
                    if profile?.displayName == nil {
                        Image(systemName: "pencil.circle.fill")
                            .foregroundStyle(.tint)
                    }
                }

                if let email = profile?.email {
                    Text(email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let joined = profile?.createdAt {
                    Text("Joined \(joined.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let provider = profile?.authProvider, !provider.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: provider == "google" ? "g.circle.fill" : "applelogo")
                            .foregroundStyle(.secondary)
                        Text("Signed in with \(provider.capitalized)")
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var initials: String {
        let name = profile?.displayName ?? profile?.email ?? "?"
        let parts = name.split(separator: " ").prefix(2)
        let chars = parts.compactMap { $0.first }.map { String($0).uppercased() }
        return chars.isEmpty ? String(name.prefix(1)).uppercased() : chars.joined()
    }

    // MARK: - Stats

    private var statGrid: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Lifetime")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                statCard(
                    title: "Total spent",
                    value: CurrencyFormatter.string(for: lifetimeSpent, currency: base),
                    icon: "arrow.up.right.circle.fill",
                    tint: theme.current.expenseColor
                )
                statCard(
                    title: "Transactions",
                    value: "\(transactions.count)",
                    icon: "list.bullet.rectangle.fill",
                    tint: .blue
                )
                statCard(
                    title: "Accounts",
                    value: "\(accounts.count)",
                    icon: "wallet.pass.fill",
                    tint: theme.current.incomeColor
                )
                statCard(
                    title: "Net worth",
                    value: CurrencyFormatter.string(for: netWorth, currency: base),
                    icon: "chart.line.uptrend.xyaxis",
                    tint: .purple
                )
            }
            .padding(.horizontal, 16)
        }
    }

    private func statCard(title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).font(.title2).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(theme.current.numericFont(.title3, weight: .bold))
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .themedCard()
    }

    private var lifetimeSpent: Decimal {
        transactions
            .filter { $0.amount < 0 }
            .reduce(Decimal(0)) { acc, tx in
                acc + (-tx.amountInBase(base) { fx.convert($0, from: $1, to: $2) })
            }
    }

    private var netWorth: Decimal {
        accounts.reduce(Decimal(0)) { $0 + fx.convert($1.balance, from: $1.currency, to: base) }
    }

    // MARK: - Budget

    private func budgetCard(budget: Decimal) -> some View {
        let startOfMonth = Calendar.current.date(from:
            Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
        let spend: Decimal = transactions
            .filter { $0.amount < 0 && $0.date >= startOfMonth }
            .reduce(Decimal(0)) { acc, tx in
                acc + (-tx.amountInBase(base) { fx.convert($0, from: $1, to: $2) })
            }
        let pct = NSDecimalNumber(decimal: spend).doubleValue
            / max(0.01, NSDecimalNumber(decimal: budget).doubleValue)

        return VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "This month")
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(CurrencyFormatter.string(for: spend, currency: base))
                        .font(theme.current.numericFont(.title2, weight: .bold))
                    Text("of \(CurrencyFormatter.string(for: budget, currency: base))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                ProgressView(value: min(pct, 1.0))
                    .tint(pct < 0.75 ? theme.current.incomeColor :
                            (pct < 1.0 ? .orange : theme.current.expenseColor))
                Text(pct > 1.0
                     ? "\(Int((pct - 1.0) * 100))% over budget"
                     : "\(Int((1 - pct) * 100))% remaining")
                    .font(.caption)
                    .foregroundStyle(pct > 1.0 ? theme.current.expenseColor : .secondary)
            }
            .padding(16)
            .themedCard()
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Accounts

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Accounts")
            if accounts.isEmpty {
                Text("No accounts yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .themedCard()
                    .padding(.horizontal, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(accounts) { a in
                        HStack(spacing: 12) {
                            IconTile(systemImage: a.kind.systemImage, tint: theme.current.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.name).font(.body)
                                Text(a.kind.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(CurrencyFormatter.string(for: a.balance, currency: a.currency))
                                .font(theme.current.numericFont(.callout))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 10)
                        if a.id != accounts.last?.id { RowDivider() }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .themedCard()
                .padding(.horizontal, 16)
            }
        }
    }
}
