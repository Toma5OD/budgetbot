import SwiftUI
import SwiftData

/// "Stupidest purchases" screen. Lists every transaction the user has
/// flagged with `isRegret = true`, ranked by absolute amount so the
/// biggest L sits at the top. Pure read view — flagging happens in
/// `TransactionDetailView`.
struct HallOfShameView: View {
    @Environment(FXService.self) private var fx
    @Environment(ThemeManager.self) private var theme

    @Query(filter: #Predicate<Transaction> { $0.isRegret && $0.confirmed },
           sort: \Transaction.date,
           order: .reverse)
    private var regrets: [Transaction]

    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    @State private var sort: Sort = .biggest

    enum Sort: String, CaseIterable, Identifiable {
        case biggest = "Biggest L"
        case recent  = "Most recent"
        var id: String { rawValue }
    }

    private var base: String {
        profiles.first?.baseCurrency ?? Currencies.localeDefault
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                if !regrets.isEmpty {
                    Picker("", selection: $sort) {
                        ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)

                    if !breakdown.isEmpty { emojiBreakdown }
                    list
                } else {
                    emptyState
                }
            }
            .padding(.vertical, 14)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Hall of Shame")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: Transaction.self) { tx in
            TransactionDetailView(tx: tx)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(roast)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .tracking(0.4)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(CurrencyFormatter.string(for: totalRegret, currency: base))
                    .font(.system(size: 42, weight: .black, design: theme.current.numericDesign))
                    .foregroundStyle(theme.current.expenseColor)
                Text("of regret")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                stat("Items", "\(regrets.count)")
                if regrets.count > 0 {
                    stat("Avg", CurrencyFormatter.string(for: avgRegret, currency: base))
                }
                if let worst = topRegret {
                    stat("Worst", worst.payee)
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .themedCard()
        .padding(.horizontal, 16)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .tracking(0.5)
            Text(value)
                .font(.subheadline.bold())
                .lineLimit(1)
        }
    }

    // MARK: - Emoji breakdown

    private var emojiBreakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("By vibe")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(breakdown, id: \.emoji) { row in
                        VStack(spacing: 4) {
                            Text(row.emoji).font(.system(size: 28))
                            Text(CurrencyFormatter.string(for: row.total, currency: base))
                                .font(.caption.bold().monospacedDigit())
                            Text("\(row.count) item\(row.count == 1 ? "" : "s")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 10)
                        .frame(width: 110)
                        .themedCard()
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - List

    private var list: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Every L, in order")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                ForEach(sortedRegrets) { tx in
                    NavigationLink(value: tx) {
                        RegretRow(tx: tx, base: base, fx: fx)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 4)
                    }
                    .buttonStyle(.plain)
                    if tx.id != sortedRegrets.last?.id { RowDivider() }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .themedCard()
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("Squeaky clean.")
                .font(.title3.bold())
            Text("Open any transaction and tap **Mark as silly purchase** to nominate it. Then come back here to wallow.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Derived

    private var totalRegret: Decimal {
        regrets.reduce(Decimal(0)) { acc, tx in
            acc + (-tx.amountInBase(base) { fx.convert($0, from: $1, to: $2) })
        }
    }

    private var avgRegret: Decimal {
        guard !regrets.isEmpty else { return 0 }
        return totalRegret / Decimal(regrets.count)
    }

    private var topRegret: Transaction? {
        regrets.max { lhs, rhs in
            let l = (-lhs.amountInBase(base) { fx.convert($0, from: $1, to: $2) })
            let r = (-rhs.amountInBase(base) { fx.convert($0, from: $1, to: $2) })
            return l < r
        }
    }

    private var sortedRegrets: [Transaction] {
        switch sort {
        case .recent:
            return regrets
        case .biggest:
            return regrets.sorted { lhs, rhs in
                let l = (-lhs.amountInBase(base) { fx.convert($0, from: $1, to: $2) })
                let r = (-rhs.amountInBase(base) { fx.convert($0, from: $1, to: $2) })
                return l > r
            }
        }
    }

    struct BreakdownRow {
        let emoji: String
        let count: Int
        let total: Decimal
    }

    private var breakdown: [BreakdownRow] {
        let groups = Dictionary(grouping: regrets) { $0.regretEmoji ?? "🤡" }
        return groups.map { emoji, txs in
            let total = txs.reduce(Decimal(0)) { acc, tx in
                acc + (-tx.amountInBase(base) { fx.convert($0, from: $1, to: $2) })
            }
            return BreakdownRow(emoji: emoji, count: txs.count, total: total)
        }
        .sorted { $0.total > $1.total }
    }

    /// Tongue-in-cheek header copy that adapts to how deep the user is in.
    private var roast: String {
        switch regrets.count {
        case 0:  return "WALL OF SAINTS"
        case 1:  return "OFF TO A START"
        case 2...4: return "WALL OF SHAME"
        case 5...9: return "BUILDING A COLLECTION"
        case 10...19: return "ESCALATING"
        default: return "ARE YOU OK?"
        }
    }
}

// MARK: - Row

private struct RegretRow: View {
    let tx: Transaction
    let base: String
    let fx: FXService

    var body: some View {
        HStack(spacing: 12) {
            Text(tx.regretEmoji ?? "🤡")
                .font(.title2)
            VStack(alignment: .leading, spacing: 3) {
                Text(tx.payee).font(.body.bold())
                HStack(spacing: 4) {
                    Text(tx.date.formatted(date: .abbreviated, time: .omitted))
                    if let cat = tx.category {
                        Text("· \(cat.name)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                if let note = tx.regretNote, !note.isEmpty {
                    Text("\u{201C}\(note)\u{201D}")
                        .font(.caption.italic())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(CurrencyFormatter.string(for: tx.amount, currency: tx.currency))
                    .font(.callout.bold().monospacedDigit())
                    .foregroundStyle(.red)
                if tx.currency != base {
                    let converted = fx.convert(tx.amount, from: tx.currency, to: base)
                    Text("≈ \(CurrencyFormatter.string(for: converted, currency: base))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}
