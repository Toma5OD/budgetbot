import SwiftUI
import SwiftData
import Charts

struct AnalyticsView: View {
    @Environment(\.modelContext) private var context
    @Environment(FXService.self) private var fx
    @Query(filter: #Predicate<Transaction> { $0.confirmed }, sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @Query(sort: \AIRecommendation.createdAt, order: .reverse) private var recs: [AIRecommendation]

    @State private var range: Range = .month
    @State private var loadingRecs = false
    @State private var error: String?

    enum Range: String, CaseIterable, Identifiable {
        case week = "Week", month = "Month", quarter = "Quarter", year = "Year"
        var id: String { rawValue }
        var days: Int { switch self { case .week: 7; case .month: 30; case .quarter: 90; case .year: 365 } }
    }

    private var base: String {
        profiles.first?.baseCurrency ?? profiles.first?.defaultCurrency ?? "USD"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Picker("", selection: $range) {
                        ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Date range")

                    summaryCards
                    flowChart
                    categoryBreakdown
                    recommendationsSection
                }
                .padding()
            }
            .navigationTitle("Analytics")
        }
    }

    // MARK: - Aggregations (all in base currency)

    private var inRange: [Transaction] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -range.days, to: Date()) ?? Date()
        return transactions.filter { $0.date >= cutoff }
    }

    private func toBase(_ tx: Transaction) -> Decimal {
        tx.amountInBase(base) { amt, from, to in fx.convert(amt, from: from, to: to) }
    }

    private var income: Decimal {
        inRange.filter { $0.amount > 0 }.reduce(0) { $0 + toBase($1) }
    }
    private var expense: Decimal {
        inRange.filter { $0.amount < 0 }.reduce(0) { $0 - toBase($1) }
    }

    // MARK: - Sections

    private var summaryCards: some View {
        HStack(spacing: 12) {
            SummaryCard(title: "In",  value: income,           currency: base, color: .green)
            SummaryCard(title: "Out", value: expense,          currency: base, color: .red)
            SummaryCard(title: "Net", value: income - expense, currency: base,
                        color: (income - expense) >= 0 ? .green : .red)
        }
    }

    private var flowChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cash flow").font(.headline)
            if inRange.isEmpty {
                EmptyState(text: "No transactions yet — capture something on the first tab.")
            } else {
                Chart(byDay) { d in
                    BarMark(x: .value("Day", d.date, unit: .day),
                            y: .value("Amount", NSDecimalNumber(decimal: d.amount).doubleValue))
                        .foregroundStyle(d.amount >= 0 ? Color.green : Color.red)
                }
                .frame(height: 220)
                .accessibilityLabel("Daily cash flow")
            }
        }
    }

    private var categoryBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Where it goes").font(.headline)
            if byCategory.isEmpty {
                EmptyState(text: "No expense data yet for this range.")
            } else {
                Chart(byCategory) { c in
                    SectorMark(angle: .value("Amount", NSDecimalNumber(decimal: c.amount).doubleValue),
                               innerRadius: .ratio(0.55),
                               angularInset: 1.5)
                        .foregroundStyle(by: .value("Category", c.name))
                }
                .frame(height: 240)
                // Legend separately so labels don't overlap slices.
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(byCategory) { c in
                        HStack {
                            Text(c.name).font(.caption)
                            Spacer()
                            Text(CurrencyFormatter.string(for: c.amount, currency: base))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI recommendations").font(.headline)
                Spacer()
                Button {
                    Task { await loadRecommendations() }
                } label: {
                    if loadingRecs {
                        ProgressView()
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(loadingRecs || inRange.isEmpty)
                .accessibilityLabel("Refresh AI recommendations")
            }

            if let error {
                Text(error).foregroundStyle(.red).font(.caption)
            }

            if recs.filter({ !$0.dismissed }).isEmpty {
                EmptyState(text: "Tap refresh to ask the AI for ideas on cuts and savings.")
            } else {
                ForEach(recs.filter { !$0.dismissed }) { r in
                    RecommendationCard(rec: r, currency: base) {
                        r.dismissed = true
                        try? context.save()
                    }
                }
            }
        }
    }

    struct Daily: Identifiable { let id = UUID(); let date: Date; let amount: Decimal }
    struct CatTotal: Identifiable { let id = UUID(); let name: String; let amount: Decimal }

    private var byDay: [Daily] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: inRange) { cal.startOfDay(for: $0.date) }
        return groups
            .map { Daily(date: $0.key, amount: $0.value.reduce(Decimal(0)) { $0 + toBase($1) }) }
            .sorted { $0.date < $1.date }
    }

    private var byCategory: [CatTotal] {
        let expenses = inRange.filter { $0.amount < 0 }
        let groups = Dictionary(grouping: expenses) { $0.category?.name ?? "Other" }
        return groups
            .map { CatTotal(name: $0.key, amount: $0.value.reduce(Decimal(0)) { $0 + -toBase($1) }) }
            .sorted { $0.amount > $1.amount }
            .prefix(8)
            .map { $0 }
    }

    // MARK: - AI

    private func loadRecommendations() async {
        loadingRecs = true
        defer { loadingRecs = false }
        error = nil

        let summary = buildSummary()
        do {
            let model = profiles.first?.aiModel ?? AIService.defaultModel
            guard let service = AIService.fromKeychain(model: model) else {
                self.error = "No AI API key set. Add one in Settings."
                return
            }
            let wires = try await service.recommendations(for: summary, defaultCurrency: base)
            for old in recs where !old.dismissed { context.delete(old) }
            for w in wires {
                let kind = RecommendationKind(rawValue: w.kind) ?? .general
                let r = AIRecommendation(
                    kind: kind,
                    title: w.title,
                    body: w.body,
                    estimatedMonthlySavings: w.estimated_monthly_savings.map { Decimal($0) }
                )
                context.insert(r)
            }
            try? context.save()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func buildSummary() -> String {
        var s = "Base currency: \(base)\nRange: last \(range.days) days\n\n"
        s += "Totals (\(base)): in=\(income), out=\(expense), net=\(income - expense)\n\n"
        s += "By category (expenses, \(base)):\n"
        for c in byCategory.prefix(12) {
            s += "- \(c.name): \(c.amount)\n"
        }
        s += "\nRecent transactions (newest first, up to 50, converted to \(base) where needed):\n"
        for tx in inRange.prefix(50) {
            let cat = tx.category?.name ?? "Uncategorised"
            let amt = toBase(tx)
            let df = ISO8601DateFormatter()
            df.formatOptions = [.withFullDate]
            s += "\(df.string(from: tx.date)) | \(tx.payee) | \(cat) | \(amt) \(base)\n"
        }
        return s
    }
}

private struct SummaryCard: View {
    let title: String
    let value: Decimal
    let currency: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(CurrencyFormatter.string(for: value, currency: currency))
                .font(.title3.bold())
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(CurrencyFormatter.string(for: value, currency: currency))")
    }
}

private struct EmptyState: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct RecommendationCard: View {
    let rec: AIRecommendation
    let currency: String
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(rec.kind.rawValue.capitalized, systemImage: icon)
                    .font(.caption.bold())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(tint.opacity(0.18), in: Capsule())
                    .foregroundStyle(tint)
                Spacer()
                if let s = rec.estimatedMonthlySavings, s > 0 {
                    Text("~\(CurrencyFormatter.string(for: s, currency: currency))/mo")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                        .accessibilityLabel("Estimated monthly savings \(CurrencyFormatter.string(for: s, currency: currency))")
                }
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .accessibilityLabel("Dismiss recommendation")
            }
            Text(rec.title).font(.headline)
            Text(rec.body).font(.callout).foregroundStyle(.secondary)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch rec.kind {
        case .silly: "exclamationmark.bubble.fill"
        case .savings: "leaf.fill"
        case .general: "lightbulb.fill"
        }
    }
    private var tint: Color {
        switch rec.kind {
        case .silly: .orange
        case .savings: .green
        case .general: .blue
        }
    }
}
