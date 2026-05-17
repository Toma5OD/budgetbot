import SwiftUI
import SwiftData

/// Dedicated page for everything recurring. Surfaces three totals at
/// the top (monthly / yearly / lifetime), then per-rule cards showing
/// what each subscription has cost over those windows. Tap a row to
/// drill into transaction history.
struct SubscriptionsView: View {
    @Environment(\.modelContext) private var context
    @Environment(FXService.self) private var fx
    @Environment(ThemeManager.self) private var theme

    @Query(filter: #Predicate<RecurringRule> { !$0.dismissed },
           sort: \RecurringRule.lastSeen, order: .reverse)
    private var rules: [RecurringRule]
    @Query private var allTransactions: [Transaction]
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    private var base: String {
        profiles.first?.baseCurrency
            ?? profiles.first?.defaultCurrency
            ?? Currencies.localeDefault
    }

    var body: some View {
        Group {
            if rules.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 18) {
                        totalsCard
                        list
                    }
                    .padding(.vertical, 12)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Subscriptions")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: RecurringRule.self) { rule in
            SubscriptionDetailView(rule: rule)
        }
    }

    // MARK: - Totals

    private var totalsCard: some View {
        let totals = computeTotals()
        return VStack(alignment: .leading, spacing: 12) {
            Text("All in").font(.caption.bold()).tracking(0.6).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Per month").font(.caption2).foregroundStyle(.tertiary)
                    AnimatedDecimal(
                        target: totals.monthly, currency: base,
                        font: .title.bold().monospacedDigit(),
                        color: theme.current.expenseColor
                    )
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Per year").font(.caption2).foregroundStyle(.tertiary)
                    Text(CurrencyFormatter.string(for: totals.yearly, currency: base))
                        .font(.title3.bold().monospacedDigit())
                }
            }
            Divider()
            HStack {
                Image(systemName: "infinity")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text("Lifetime")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(CurrencyFormatter.string(for: totals.lifetime, currency: base))
                    .font(.callout.bold().monospacedDigit())
                    .foregroundStyle(theme.current.expenseColor)
            }
        }
        .padding(18)
        .themedCard()
        .padding(.horizontal, 16)
    }

    // MARK: - List

    private var list: some View {
        VStack(spacing: 10) {
            ForEach(rules) { rule in
                NavigationLink(value: rule) {
                    subscriptionRow(rule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    private func subscriptionRow(_ rule: RecurringRule) -> some View {
        let stats = stats(for: rule)
        return HStack(spacing: 12) {
            BrandLogoView(subscriptionName: rule.displayName,
                          categoryName: rule.category?.name,
                          size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.displayName).font(.callout.bold())
                HStack(spacing: 6) {
                    Text(rule.cadence.displayName)
                    Text("· seen \(rule.occurrences)×")
                    if let cat = rule.category {
                        Text("· \(cat.name)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(CurrencyFormatter.string(for: stats.monthly, currency: base))
                    .font(.callout.bold().monospacedDigit())
                    .foregroundStyle(theme.current.expenseColor)
                Text("/mo · \(CurrencyFormatter.string(for: stats.lifetime, currency: base)) lifetime")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .themedCard()
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Nothing recurring yet").font(.title3.bold())
            Text("Once you have 3+ charges from the same place — phone bill, Netflix, electricity — we'll group them here automatically.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Math

    private struct Totals {
        let monthly: Decimal
        let yearly: Decimal
        let lifetime: Decimal
    }

    private func computeTotals() -> Totals {
        var monthly: Decimal = 0
        var lifetime: Decimal = 0
        for rule in rules {
            let s = stats(for: rule)
            monthly += s.monthly
            lifetime += s.lifetime
        }
        return Totals(monthly: monthly, yearly: monthly * 12, lifetime: lifetime)
    }

    private struct RuleStats {
        let monthly: Decimal
        let lifetime: Decimal
    }

    private func stats(for rule: RecurringRule) -> RuleStats {
        let monthly = -fx.convert(rule.monthlyEstimate,
                                  from: rule.currency, to: base)
        // Lifetime: prefer the actual matched-transaction total when
        // we have it (more accurate than rate × occurrences), fall
        // back to the cadence-rate estimate otherwise.
        let linked = allTransactions.filter { $0.recurringRuleID == rule.id }
        let lifetimeFromTx: Decimal = linked.reduce(0) { acc, tx in
            acc + (-tx.amountInBase(base) { fx.convert($0, from: $1, to: $2) })
        }
        let lifetimeFromRule = monthly * Decimal(rule.occurrences) *
            (rule.cadence == .yearly ? 12 :
             rule.cadence == .weekly ? Decimal(1) / 4 : 1)
        let lifetime = lifetimeFromTx > 0 ? lifetimeFromTx : lifetimeFromRule
        return RuleStats(monthly: monthly, lifetime: lifetime)
    }
}

// MARK: - Detail

struct SubscriptionDetailView: View {
    @Bindable var rule: RecurringRule
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(FXService.self) private var fx
    @Environment(ThemeManager.self) private var theme

    @Query private var allTransactions: [Transaction]
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    private var base: String {
        profiles.first?.baseCurrency
            ?? profiles.first?.defaultCurrency
            ?? Currencies.localeDefault
    }

    private var matched: [Transaction] {
        allTransactions
            .filter { $0.recurringRuleID == rule.id }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                stats
                if !matched.isEmpty { transactions }
                dangerZone
            }
            .padding(16)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle(rule.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                BrandLogoView(subscriptionName: rule.displayName,
                              categoryName: rule.category?.name,
                              size: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(rule.displayName).font(.headline)
                    Text("\(rule.cadence.displayName) · seen \(rule.occurrences)×")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            AnimatedDecimal(
                target: -fx.convert(rule.monthlyEstimate, from: rule.currency, to: base),
                currency: base,
                font: .system(size: 38, weight: .black, design: theme.current.numericDesign),
                color: theme.current.expenseColor
            )
            Text("per month")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .themedCard()
    }

    private var stats: some View {
        let monthly = -fx.convert(rule.monthlyEstimate, from: rule.currency, to: base)
        let yearly = monthly * 12
        let lifetimeMatched: Decimal = matched.reduce(0) { acc, tx in
            acc + (-tx.amountInBase(base) { fx.convert($0, from: $1, to: $2) })
        }
        return HStack(spacing: 10) {
            statTile("Yearly", CurrencyFormatter.string(for: yearly, currency: base))
            statTile("Lifetime",
                     CurrencyFormatter.string(for: lifetimeMatched > 0 ? lifetimeMatched : monthly * Decimal(rule.occurrences),
                                              currency: base))
            statTile("First seen",
                     rule.firstSeen.formatted(date: .abbreviated, time: .omitted))
        }
    }

    private func statTile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.tertiary)
            Text(value).font(.callout.bold().monospacedDigit())
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .themedCard()
    }

    private var transactions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent charges").font(.subheadline.bold())
            VStack(spacing: 0) {
                ForEach(matched.prefix(12)) { tx in
                    HStack {
                        Text(tx.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(CurrencyFormatter.string(for: tx.amount, currency: tx.currency))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.red)
                    }
                    .padding(.vertical, 6)
                    if tx.id != matched.prefix(12).last?.id { Divider() }
                }
            }
            .padding(.horizontal, 12)
            .themedCard()
        }
    }

    private var dangerZone: some View {
        VStack(spacing: 10) {
            Button(role: .destructive) {
                rule.dismissed = true
                try? context.save()
                dismiss()
            } label: {
                Label("Dismiss subscription", systemImage: "xmark.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.red.opacity(0.12), in: Capsule())
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            Text("Dismissed subscriptions are hidden from analytics and the home screen. Future charges from this merchant still appear in the regular transaction list.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }
}
