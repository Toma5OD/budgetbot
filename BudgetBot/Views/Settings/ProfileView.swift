import SwiftUI
import SwiftData

/// User profile screen. Avatar with initials, editable display name,
/// lifetime totals, this-month progress against budget.
struct ProfileView: View {
    @Environment(\.modelContext) private var context
    @Environment(FXService.self) private var fx
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @Query(filter: #Predicate<Transaction> { $0.confirmed }) private var transactions: [Transaction]
    @Query(filter: #Predicate<Account> { !$0.archived }) private var accounts: [Account]

    @State private var editingName = false
    @State private var nameDraft = ""

    private var profile: UserProfile? { profiles.first }

    private var base: String {
        profile?.baseCurrency ?? profile?.defaultCurrency ?? Currencies.localeDefault
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                avatarBlock
                statsGrid
                if let p = profile, let budget = p.monthlyBudget, budget > 0 {
                    budgetCard(budget: budget)
                }
                accountsSummary
            }
            .padding()
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Display name", isPresented: $editingName) {
            TextField("Name", text: $nameDraft)
            Button("Save") {
                profile?.displayName = nameDraft.trimmingCharacters(in: .whitespaces).isEmpty
                    ? nil : nameDraft.trimmingCharacters(in: .whitespaces)
                try? context.save()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Avatar

    private var avatarBlock: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 110, height: 110)
                Text(initials)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            }
            .shadow(color: Color.accentColor.opacity(0.35), radius: 12, x: 0, y: 6)

            Button {
                nameDraft = profile?.displayName ?? ""
                editingName = true
            } label: {
                HStack(spacing: 4) {
                    Text(profile?.displayName ?? "Set your name")
                        .font(.title2.bold())
                    Image(systemName: "pencil")
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                }
            }
            .buttonStyle(.plain)

            if let email = profile?.email {
                Text(email).font(.callout).foregroundStyle(.secondary)
            }

            if let joined = profile?.createdAt {
                Text("Joined \(joined.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var initials: String {
        let name = profile?.displayName ?? profile?.email ?? "?"
        let parts = name.split(separator: " ").prefix(2)
        let chars = parts.compactMap { $0.first }.map { String($0).uppercased() }
        return chars.isEmpty ? String(name.prefix(1)).uppercased() : chars.joined()
    }

    // MARK: - Stats

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statCard(
                title: "Total spent",
                value: CurrencyFormatter.string(for: lifetimeSpent, currency: base),
                icon: "arrow.up.right.circle.fill",
                tint: .red
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
                tint: .green
            )
            statCard(
                title: "Net worth",
                value: CurrencyFormatter.string(for: netWorth, currency: base),
                icon: "chart.line.uptrend.xyaxis",
                tint: .purple
            )
        }
    }

    private func statCard(title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.title2).foregroundStyle(tint)
            Text(value).font(.title3.bold()).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
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

    // MARK: - Budget progress (this month)

    private func budgetCard(budget: Decimal) -> some View {
        let startOfMonth = Calendar.current.date(from:
            Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
        let monthSpend: Decimal = transactions
            .filter { $0.amount < 0 && $0.date >= startOfMonth }
            .reduce(Decimal(0)) { acc, tx in
                acc + (-tx.amountInBase(base) { fx.convert($0, from: $1, to: $2) })
            }
        let pct = NSDecimalNumber(decimal: monthSpend).doubleValue
            / max(0.01, NSDecimalNumber(decimal: budget).doubleValue)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("This month", systemImage: "calendar")
                    .font(.headline)
                Spacer()
                Text("\(CurrencyFormatter.string(for: monthSpend, currency: base)) / \(CurrencyFormatter.string(for: budget, currency: base))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(pct, 1.0))
                .tint(pct < 0.75 ? .green : (pct < 1.0 ? .orange : .red))
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Accounts summary

    private var accountsSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Accounts").font(.headline)
            if accounts.isEmpty {
                Text("No accounts yet.").font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(accounts) { a in
                        HStack {
                            Image(systemName: a.kind.systemImage).foregroundStyle(.tint)
                            Text(a.name)
                            Spacer()
                            Text(CurrencyFormatter.string(for: a.balance, currency: a.currency))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                        if a.id != accounts.last?.id { Divider() }
                    }
                }
                .padding(.horizontal)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}
