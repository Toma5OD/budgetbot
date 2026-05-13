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
    @State private var customStart: Date = Calendar.current.date(byAdding: .day, value: -30, to: .now)!
    @State private var customEnd: Date = .now
    @State private var loadingRecs = false
    @State private var error: String?
    @State private var drilldown: Drilldown?

    enum Range: String, CaseIterable, Identifiable {
        case week = "Week", month = "Month", quarter = "Quarter", year = "Year", custom = "Custom"
        var id: String { rawValue }
        var days: Int? {
            switch self {
            case .week: 7; case .month: 30; case .quarter: 90; case .year: 365
            case .custom: nil
            }
        }
    }

    /// Sheet payload for drill-down into the filtered tx list.
    struct Drilldown: Identifiable {
        let id = UUID()
        let title: String
        let txs: [Transaction]
    }

    private var base: String {
        profiles.first?.baseCurrency ?? profiles.first?.defaultCurrency ?? Currencies.localeDefault
    }

    private var hasIncome: Bool {
        transactions.contains { $0.amount > 0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    rangePicker
                    summaryCards
                    if let budget = profiles.first?.monthlyBudget, budget > 0, range == .month {
                        budgetCard(budget: budget)
                    }
                    flowChart
                    categoryBreakdown
                    topMerchants
                    dayOfWeekChart
                    periodComparison
                    recommendationsSection
                }
                .padding()
            }
            .navigationTitle("Analytics")
            .sheet(item: $drilldown) { d in
                DrilldownSheet(title: d.title, txs: d.txs, base: base, fx: fx)
            }
        }
    }

    // MARK: - Range

    private var rangePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $range) {
                ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if range == .custom {
                HStack {
                    DatePicker("From", selection: $customStart, displayedComponents: .date).labelsHidden()
                    Text("→")
                    DatePicker("To", selection: $customEnd, displayedComponents: .date).labelsHidden()
                }
                .font(.caption)
            }
        }
    }

    // MARK: - Aggregations

    private var inRange: [Transaction] {
        let (start, end) = bounds()
        return transactions.filter { $0.date >= start && $0.date <= end }
    }

    private func bounds() -> (Date, Date) {
        switch range {
        case .custom:
            let s = Calendar.current.startOfDay(for: customStart)
            let e = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: customEnd)) ?? customEnd
            return (s, e)
        default:
            let days = range.days ?? 30
            let s = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            return (s, Date())
        }
    }

    private func toBase(_ tx: Transaction) -> Decimal {
        tx.amountInBase(base) { fx.convert($0, from: $1, to: $2) }
    }

    private var income: Decimal {
        inRange.filter { $0.amount > 0 }.reduce(0) { $0 + toBase($1) }
    }
    private var expense: Decimal {
        inRange.filter { $0.amount < 0 }.reduce(0) { $0 - toBase($1) }
    }

    // MARK: - Summary

    private var summaryCards: some View {
        HStack(spacing: 12) {
            if hasIncome {
                SummaryCard(title: "In",  value: income, currency: base, color: .green)
                SummaryCard(title: "Out", value: expense, currency: base, color: .red)
                SummaryCard(title: "Net", value: income - expense, currency: base,
                            color: (income - expense) >= 0 ? .green : .red)
            } else {
                SummaryCard(title: "Spent", value: expense, currency: base, color: .red,
                            wide: true,
                            subtitle: dailyAverageLabel)
                SummaryCard(title: "Tx", value: Decimal(inRange.filter { $0.amount < 0 }.count),
                            currency: nil, color: .blue, isCount: true)
            }
        }
    }

    private var dailyAverageLabel: String? {
        let days = max(1, daysInRange)
        let avg = expense / Decimal(days)
        return "≈ \(CurrencyFormatter.string(for: avg, currency: base))/day"
    }

    private var daysInRange: Int {
        let (s, e) = bounds()
        return max(1, Calendar.current.dateComponents([.day], from: s, to: e).day ?? 1)
    }

    // MARK: - Budget

    private func budgetCard(budget: Decimal) -> some View {
        let spent = expense
        let pct = NSDecimalNumber(decimal: spent).doubleValue
            / max(0.01, NSDecimalNumber(decimal: budget).doubleValue)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Monthly budget").font(.headline)
                Spacer()
                Text("\(CurrencyFormatter.string(for: spent, currency: base)) / \(CurrencyFormatter.string(for: budget, currency: base))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(pct, 1.0))
                .tint(pct < 0.75 ? .green : (pct < 1.0 ? .orange : .red))
            if pct > 1.0 {
                Text("\(Int((pct - 1.0) * 100))% over budget")
                    .font(.caption).foregroundStyle(.red)
            } else {
                Text("\(Int((1 - pct) * 100))% remaining")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Daily flow

    private var flowChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily spend").font(.headline)
            if inRange.isEmpty {
                EmptyState(text: "No transactions yet — capture something on the first tab.")
            } else {
                Chart(byDay) { d in
                    BarMark(
                        x: .value("Day", d.date, unit: .day),
                        y: .value("Amount", NSDecimalNumber(decimal: d.expense).doubleValue)
                    )
                    .foregroundStyle(.red.opacity(0.85))
                }
                .frame(height: 200)
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onTapGesture { location in
                                handleBarTap(location: location, proxy: proxy, geo: geo)
                            }
                    }
                }
            }
        }
    }

    private func handleBarTap(location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) {
        let plotFrame = geo[proxy.plotAreaFrame]
        guard plotFrame.contains(location),
              let date: Date = proxy.value(atX: location.x - plotFrame.origin.x) else { return }
        let day = Calendar.current.startOfDay(for: date)
        let txs = inRange.filter { Calendar.current.isDate($0.date, inSameDayAs: day) && $0.amount < 0 }
        guard !txs.isEmpty else { return }
        let df = DateFormatter(); df.dateStyle = .medium
        drilldown = Drilldown(title: df.string(from: day), txs: txs)
    }

    // MARK: - Category donut

    private var categoryBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Where it goes").font(.headline)
            if byCategory.isEmpty {
                EmptyState(text: "No expense data yet for this range.")
            } else {
                Chart(byCategory) { c in
                    SectorMark(
                        angle: .value("Amount", NSDecimalNumber(decimal: c.amount).doubleValue),
                        innerRadius: .ratio(0.55),
                        angularInset: 1.5
                    )
                    .foregroundStyle(by: .value("Category", c.name))
                }
                .frame(height: 220)

                VStack(spacing: 0) {
                    ForEach(byCategory) { c in
                        Button {
                            let txs = inRange.filter { ($0.category?.name ?? "Other") == c.name && $0.amount < 0 }
                            drilldown = Drilldown(title: c.name, txs: txs)
                        } label: {
                            HStack {
                                Text(c.name).font(.callout)
                                Spacer()
                                Text(CurrencyFormatter.string(for: c.amount, currency: base))
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        if c.id != byCategory.last?.id { Divider() }
                    }
                }
            }
        }
    }

    // MARK: - Top merchants

    private var topMerchants: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top merchants").font(.headline)
            if topPayees.isEmpty {
                EmptyState(text: "No expense data yet for this range.")
            } else {
                VStack(spacing: 0) {
                    ForEach(topPayees) { p in
                        Button {
                            let txs = inRange.filter { $0.payee == p.name && $0.amount < 0 }
                            drilldown = Drilldown(title: p.name, txs: txs)
                        } label: {
                            HStack {
                                Text(p.name).font(.callout).lineLimit(1)
                                Spacer()
                                Text("\(p.count)×").font(.caption).foregroundStyle(.secondary)
                                Text(CurrencyFormatter.string(for: p.total, currency: base))
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        if p.id != topPayees.last?.id { Divider() }
                    }
                }
            }
        }
    }

    // MARK: - Day of week

    private var dayOfWeekChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("By day of week").font(.headline)
            if byDow.allSatisfy({ $0.amount == 0 }) {
                EmptyState(text: "Not enough data yet.")
            } else {
                Chart(byDow) { d in
                    BarMark(
                        x: .value("Day", d.label),
                        y: .value("Amount", NSDecimalNumber(decimal: d.amount).doubleValue)
                    )
                    .foregroundStyle(.tint.opacity(0.85))
                }
                .frame(height: 150)
            }
        }
    }

    // MARK: - Period comparison

    private var periodComparison: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("vs previous period").font(.headline)
            HStack(spacing: 12) {
                comparisonCard(title: "This", value: expense, color: .primary)
                comparisonCard(title: "Previous", value: previousPeriodExpense, color: .secondary)
                comparisonCard(
                    title: "Change",
                    valueString: comparisonDelta,
                    color: previousPeriodExpense == 0 ? .secondary
                        : (expense <= previousPeriodExpense ? .green : .red)
                )
            }
        }
    }

    private var previousPeriodExpense: Decimal {
        let (start, end) = bounds()
        let length = end.timeIntervalSince(start)
        let prevEnd = start
        let prevStart = start.addingTimeInterval(-length)
        let txs = transactions.filter { $0.date >= prevStart && $0.date < prevEnd && $0.amount < 0 }
        return txs.reduce(0) { $0 - toBase($1) }
    }

    private var comparisonDelta: String {
        guard previousPeriodExpense > 0 else { return "—" }
        let diff = expense - previousPeriodExpense
        let pct = NSDecimalNumber(decimal: diff).doubleValue
            / NSDecimalNumber(decimal: previousPeriodExpense).doubleValue * 100
        let sign = diff > 0 ? "+" : ""
        return "\(sign)\(Int(pct.rounded()))%"
    }

    @ViewBuilder
    private func comparisonCard(title: String, value: Decimal? = nil, valueString: String? = nil, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            if let v = value {
                Text(CurrencyFormatter.string(for: v, currency: base))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(color)
            } else {
                Text(valueString ?? "—").font(.headline).foregroundStyle(color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Recommendations

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

    // MARK: - Computed series

    struct Daily: Identifiable {
        let id = UUID()
        let date: Date
        let expense: Decimal
    }
    struct CatTotal: Identifiable {
        let id = UUID()
        let name: String
        let amount: Decimal
    }
    struct PayeeTotal: Identifiable {
        let id = UUID()
        let name: String
        let total: Decimal
        let count: Int
    }
    struct DowTotal: Identifiable {
        let id = UUID()
        let weekday: Int   // 1 = Sunday
        let label: String
        let amount: Decimal
    }

    private var byDay: [Daily] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: inRange.filter { $0.amount < 0 }) {
            cal.startOfDay(for: $0.date)
        }
        return groups
            .map { Daily(date: $0.key, expense: $0.value.reduce(Decimal(0)) { $0 + -toBase($1) }) }
            .sorted { $0.date < $1.date }
    }

    private var byCategory: [CatTotal] {
        let expenses = inRange.filter { $0.amount < 0 }
        let groups = Dictionary(grouping: expenses) { $0.category?.name ?? "Other" }
        return groups
            .map { CatTotal(name: $0.key, amount: $0.value.reduce(Decimal(0)) { $0 + -toBase($1) }) }
            .sorted { $0.amount > $1.amount }
            .prefix(10)
            .map { $0 }
    }

    private var topPayees: [PayeeTotal] {
        let expenses = inRange.filter { $0.amount < 0 }
        let groups = Dictionary(grouping: expenses) { $0.payee }
        return groups
            .map { PayeeTotal(
                name: $0.key,
                total: $0.value.reduce(Decimal(0)) { $0 + -toBase($1) },
                count: $0.value.count
            ) }
            .sorted { $0.total > $1.total }
            .prefix(8)
            .map { $0 }
    }

    private var byDow: [DowTotal] {
        let cal = Calendar.current
        let labels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        var totals: [Int: Decimal] = [:]
        for tx in inRange where tx.amount < 0 {
            let dow = cal.component(.weekday, from: tx.date)
            totals[dow, default: 0] += -toBase(tx)
        }
        return (1...7).map { i in
            DowTotal(weekday: i, label: labels[i - 1], amount: totals[i] ?? 0)
        }
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
        var s = "Base currency: \(base)\nRange: \(range.rawValue.lowercased())\n\n"
        s += "Totals (\(base)): out=\(expense)"
        if hasIncome { s += ", in=\(income), net=\(income - expense)" }
        s += "\n\n"
        s += "By category (expenses, \(base)):\n"
        for c in byCategory.prefix(12) {
            s += "- \(c.name): \(c.amount)\n"
        }
        s += "\nTop merchants:\n"
        for p in topPayees {
            s += "- \(p.name): \(p.total) (\(p.count) tx)\n"
        }
        s += "\nRecent transactions (newest first, up to 60, in \(base)):\n"
        for tx in inRange.prefix(60) {
            let cat = tx.category?.name ?? "Uncategorised"
            let amt = toBase(tx)
            let df = ISO8601DateFormatter()
            df.formatOptions = [.withFullDate]
            s += "\(df.string(from: tx.date)) | \(tx.payee) | \(cat) | \(amt) \(base)\n"
        }
        return s
    }
}

// MARK: - Subviews

private struct SummaryCard: View {
    let title: String
    let value: Decimal
    let currency: String?
    let color: Color
    var wide: Bool = false
    var subtitle: String? = nil
    var isCount: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(formatted)
                .font(wide ? .title.bold() : .title3.bold())
                .monospacedDigit()
                .foregroundStyle(color)
            if let subtitle {
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(formatted)")
    }

    private var formatted: String {
        if isCount {
            return "\(NSDecimalNumber(decimal: value).intValue)"
        }
        if let currency {
            return CurrencyFormatter.string(for: value, currency: currency)
        }
        return "\(value)"
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

/// Sheet shown when the user taps a category, bar, or merchant.
private struct DrilldownSheet: View {
    let title: String
    let txs: [Transaction]
    let base: String
    let fx: FXService

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Total").font(.headline)
                        Spacer()
                        Text(CurrencyFormatter.string(for: total, currency: base))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.red)
                    }
                }
                Section("\(txs.count) transaction\(txs.count == 1 ? "" : "s")") {
                    ForEach(txs.sorted { $0.date > $1.date }) { tx in
                        NavigationLink(value: tx) {
                            TransactionRow(tx: tx)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Transaction.self) { tx in
                TransactionDetailView(tx: tx)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var total: Decimal {
        txs.reduce(Decimal(0)) { acc, tx in
            acc + (-tx.amountInBase(base) { fx.convert($0, from: $1, to: $2) })
        }
    }
}
