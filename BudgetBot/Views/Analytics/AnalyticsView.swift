import SwiftUI
import SwiftData
import Charts

/// Expense-focused, interactive analytics. Aggregates via `Transaction`'s
/// `categorisedSlices(in:)` so a transaction with splits contributes one row
/// per split category, while a single-category transaction contributes one row.
/// Donut is animated and selectable. Bars are tappable. Subscriptions
/// section surfaces detected recurring expenses.
struct AnalyticsView: View {
    @Environment(\.modelContext) private var context
    @Environment(FXService.self) private var fx
    @Environment(ThemeManager.self) private var theme

    @Query(filter: #Predicate<Transaction> { $0.confirmed }, sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @Query(sort: \AIRecommendation.createdAt, order: .reverse) private var recs: [AIRecommendation]
    @Query(filter: #Predicate<RecurringRule> { !$0.dismissed },
           sort: \RecurringRule.lastSeen, order: .reverse)
    private var rules: [RecurringRule]

    @State private var range: Range = .month
    @State private var customStart: Date = Calendar.current.date(byAdding: .day, value: -30, to: .now)!
    @State private var customEnd: Date = .now
    @State private var loadingRecs = false
    @State private var error: String?
    @State private var drilldown: Drilldown?
    @State private var selectedAngle: Double?
    @State private var appearAnimation = false
    @State private var lastSubscriptionScan: Date?

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

    struct Drilldown: Identifiable {
        let id = UUID()
        let title: String
        let transactions: [Transaction]
    }

    private var base: String {
        profiles.first?.baseCurrency ?? profiles.first?.defaultCurrency ?? Currencies.localeDefault
    }
    private var palette: [Color] { theme.current.chartPalette }

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
                    subscriptionsSection
                    topMerchants
                    dayOfWeekChart
                    periodComparison
                    recommendationsSection
                }
                .padding()
                .animation(.snappy, value: range)
            }
            .navigationTitle("Analytics")
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                    appearAnimation = true
                }
                rescanSubscriptionsIfNeeded()
            }
            .sheet(item: $drilldown) { d in
                DrilldownSheet(title: d.title, transactions: d.transactions, base: base, fx: fx)
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

    // MARK: - Aggregations (via Transaction.categorisedSlices)

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

    private var inRange: [Transaction] {
        let (s, e) = bounds()
        return transactions.filter { $0.date >= s && $0.date <= e }
    }

    private func convert(_ amt: Decimal, _ from: String, _ to: String) -> Decimal {
        fx.convert(amt, from: from, to: to)
    }

    private func slices(_ tx: Transaction) -> [Transaction.CategorisedSlice] {
        tx.categorisedSlices(in: base, liveConvert: convert)
    }

    private var hasIncome: Bool { transactions.contains { $0.amount > 0 } }

    private var income: Decimal {
        inRange.flatMap(slices).filter { $0.amount > 0 }.reduce(0) { $0 + $1.amount }
    }
    private var expense: Decimal {
        inRange.flatMap(slices).filter { $0.amount < 0 }.reduce(0) { $0 - $1.amount }
    }

    private var daysInRange: Int {
        let (s, e) = bounds()
        return max(1, Calendar.current.dateComponents([.day], from: s, to: e).day ?? 1)
    }

    // MARK: - Summary

    private var summaryCards: some View {
        HStack(spacing: 12) {
            if hasIncome {
                SummaryCard(title: "In",  value: income,  currency: base, color: theme.current.incomeColor)
                SummaryCard(title: "Out", value: expense, currency: base, color: theme.current.expenseColor)
                SummaryCard(title: "Net", value: income - expense, currency: base,
                            color: (income - expense) >= 0 ? theme.current.incomeColor : theme.current.expenseColor)
            } else {
                SummaryCard(
                    title: "Spent", value: expense, currency: base,
                    color: theme.current.expenseColor, wide: true,
                    subtitle: dailyAverageLabel
                )
                SummaryCard(
                    title: "Transactions",
                    value: Decimal(inRange.count),
                    currency: nil, color: theme.current.tint, isCount: true
                )
            }
        }
    }

    private var dailyAverageLabel: String? {
        let avg = expense / Decimal(daysInRange)
        return "≈ \(CurrencyFormatter.string(for: avg, currency: base))/day"
    }

    // MARK: - Budget

    private func budgetCard(budget: Decimal) -> some View {
        let pct = NSDecimalNumber(decimal: expense).doubleValue
            / max(0.01, NSDecimalNumber(decimal: budget).doubleValue)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Monthly budget").font(.headline)
                Spacer()
                Text("\(CurrencyFormatter.string(for: expense, currency: base)) / \(CurrencyFormatter.string(for: budget, currency: base))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(pct, 1.0))
                .tint(pct < 0.75 ? theme.current.incomeColor : (pct < 1.0 ? .orange : theme.current.expenseColor))
                .animation(.spring, value: pct)
            Text(pct > 1.0 ? "\(Int((pct - 1.0) * 100))% over budget"
                          : "\(Int((1 - pct) * 100))% remaining")
                .font(.caption).foregroundStyle(pct > 1.0 ? theme.current.expenseColor : .secondary)
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
                        y: .value("Amount", appearAnimation ? NSDecimalNumber(decimal: d.expense).doubleValue : 0)
                    )
                    .foregroundStyle(theme.current.expenseColor.opacity(0.85))
                    .cornerRadius(4)
                }
                .frame(height: 200)
                .animation(.spring(response: 0.7, dampingFraction: 0.85), value: appearAnimation)
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
        drilldown = Drilldown(title: df.string(from: day), transactions: txs)
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
                        angle: .value("Amount",
                                      appearAnimation ? NSDecimalNumber(decimal: c.amount).doubleValue : 0),
                        innerRadius: .ratio(0.55),
                        outerRadius: c.id == selectedCategory?.id ? .ratio(1.0) : .ratio(0.95),
                        angularInset: 1.5
                    )
                    .cornerRadius(4)
                    .foregroundStyle(colorFor(c))
                    .opacity(selectedCategory == nil || selectedCategory?.id == c.id ? 1.0 : 0.45)
                }
                .frame(height: 240)
                .chartAngleSelection(value: $selectedAngle)
                .animation(.spring(response: 0.55, dampingFraction: 0.85), value: appearAnimation)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedCategory?.id)
                .chartBackground { _ in
                    if let sel = selectedCategory {
                        VStack(spacing: 4) {
                            Text(sel.name).font(.subheadline.bold())
                            Text(CurrencyFormatter.string(for: sel.amount, currency: base))
                                .font(.title3.bold().monospacedDigit())
                                .foregroundStyle(theme.current.expenseColor)
                            let pct = NSDecimalNumber(decimal: sel.amount).doubleValue
                                / NSDecimalNumber(decimal: max(expense, 0.01)).doubleValue
                            Text("\(Int((pct * 100).rounded()))%")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .transition(.scale.combined(with: .opacity))
                    } else {
                        VStack(spacing: 4) {
                            Text("Total").font(.caption).foregroundStyle(.secondary)
                            Text(CurrencyFormatter.string(for: expense, currency: base))
                                .font(.title3.bold().monospacedDigit())
                            Text("Tap a slice").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
                .onChange(of: selectedAngle) { _, _ in
                    if let cat = selectedCategory {
                        let txs = inRange.filter { tx in
                            slices(tx).contains { ($0.category?.name ?? "Other") == cat.name && $0.amount < 0 }
                        }
                        drilldown = Drilldown(title: cat.name, transactions: txs)
                        selectedAngle = nil
                    }
                }

                VStack(spacing: 0) {
                    ForEach(byCategory) { c in
                        Button {
                            let txs = inRange.filter { tx in
                                slices(tx).contains { ($0.category?.name ?? "Other") == c.name && $0.amount < 0 }
                            }
                            drilldown = Drilldown(title: c.name, transactions: txs)
                        } label: {
                            HStack(spacing: 10) {
                                Circle().fill(colorFor(c)).frame(width: 12, height: 12)
                                Text(c.name).font(.callout)
                                Spacer()
                                Text(CurrencyFormatter.string(for: c.amount, currency: base))
                                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption2).foregroundStyle(.tertiary)
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

    private var selectedCategory: CatTotal? {
        guard let angle = selectedAngle else { return nil }
        var cumulative: Double = 0
        let total = byCategory.reduce(0) { $0 + NSDecimalNumber(decimal: $1.amount).doubleValue }
        guard total > 0 else { return nil }
        for c in byCategory {
            cumulative += NSDecimalNumber(decimal: c.amount).doubleValue
            if angle <= cumulative { return c }
        }
        return byCategory.last
    }

    private func colorFor(_ c: CatTotal) -> Color {
        let idx = byCategory.firstIndex(where: { $0.id == c.id }) ?? 0
        return palette[idx % palette.count]
    }

    // MARK: - Subscriptions

    private var subscriptionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Subscriptions", systemImage: "repeat.circle.fill")
                    .font(.headline)
                Spacer()
                Button {
                    rescanSubscriptions(force: true)
                } label: {
                    Image(systemName: "arrow.clockwise").font(.caption)
                }
                .accessibilityLabel("Rescan subscriptions")
            }

            if rules.isEmpty {
                EmptyState(text: "I'll auto-detect recurring payments once you have at least 3 charges from the same place. Phone bills, Netflix, electricity — they all show up here.")
            } else {
                let total = rules.reduce(Decimal(0)) { acc, r in
                    acc + (-fx.convert(r.monthlyEstimate, from: r.currency, to: base))
                }
                HStack {
                    Text("Total / month").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Text(CurrencyFormatter.string(for: total, currency: base))
                        .font(.callout.bold().monospacedDigit())
                        .foregroundStyle(theme.current.expenseColor)
                }
                .padding(10)
                .background(theme.current.expenseColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

                VStack(spacing: 0) {
                    ForEach(rules) { rule in
                        SubscriptionRow(rule: rule, base: base, fx: fx) {
                            rule.dismissed = true
                            try? context.save()
                        }
                        if rule.id != rules.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private func rescanSubscriptionsIfNeeded() {
        let stale = lastSubscriptionScan == nil
            || Date().timeIntervalSince(lastSubscriptionScan!) > 6 * 3600
        if stale { rescanSubscriptions(force: false) }
    }

    private func rescanSubscriptions(force: Bool) {
        lastSubscriptionScan = Date()
        let snaps: [SubscriptionDetector.Snapshot] = transactions.map { tx in
            .init(
                id: tx.id, date: tx.date, payee: tx.payee, amount: tx.amount,
                currency: tx.currency, categoryName: tx.category?.name
            )
        }
        let candidates = SubscriptionDetector().detect(in: snaps)
        let existingByID = Dictionary(uniqueKeysWithValues: rules.map { ($0.id, $0) })
        let existingKeys = Set(rules.map { Self.ruleKey(payee: $0.payeePattern, cadence: $0.cadence, currency: $0.currency) })

        // Insert or update.
        for c in candidates {
            let key = Self.ruleKey(payee: c.payeeKey, cadence: c.cadence, currency: c.currency)
            if let existing = rules.first(where: {
                Self.ruleKey(payee: $0.payeePattern, cadence: $0.cadence, currency: $0.currency) == key
            }) {
                existing.expectedAmount = c.expectedAmount
                existing.displayName = c.displayName
                existing.lastSeen = c.lastSeen
                existing.occurrences = c.occurrences
            } else if !existingKeys.contains(key) {
                let cat = c.category.flatMap { name in
                    (try? context.fetch(FetchDescriptor<TxCategory>()))?
                        .first { $0.name.lowercased() == name.lowercased() }
                }
                let acc = (try? context.fetch(FetchDescriptor<Account>()))?.first
                let rule = RecurringRule(
                    payeePattern: c.payeeKey,
                    displayName: c.displayName,
                    expectedAmount: c.expectedAmount,
                    currency: c.currency,
                    cadence: c.cadence,
                    firstSeen: c.firstSeen,
                    lastSeen: c.lastSeen,
                    occurrences: c.occurrences,
                    category: cat,
                    account: acc
                )
                context.insert(rule)
            }
        }
        _ = existingByID  // silence unused
        try? context.save()
    }

    static func ruleKey(payee: String, cadence: RecurringRule.Cadence, currency: String) -> String {
        "\(payee)__\(cadence.rawValue)__\(currency)"
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
                            drilldown = Drilldown(title: p.name, transactions: txs)
                        } label: {
                            HStack {
                                Text(p.name).font(.callout).lineLimit(1)
                                Spacer()
                                Text("\(p.count)×").font(.caption).foregroundStyle(.secondary)
                                Text(CurrencyFormatter.string(for: p.total, currency: base))
                                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption2).foregroundStyle(.tertiary)
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
                        y: .value("Amount", appearAnimation ? NSDecimalNumber(decimal: d.amount).doubleValue : 0)
                    )
                    .foregroundStyle(theme.current.tint.opacity(0.85))
                    .cornerRadius(4)
                }
                .frame(height: 150)
                .animation(.spring(response: 0.7, dampingFraction: 0.85), value: appearAnimation)
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
                        : (expense <= previousPeriodExpense ? theme.current.incomeColor : theme.current.expenseColor)
                )
            }
        }
    }

    private var previousPeriodExpense: Decimal {
        let (start, end) = bounds()
        let length = end.timeIntervalSince(start)
        let prevEnd = start
        let prevStart = start.addingTimeInterval(-length)
        let txs = transactions.filter { $0.date >= prevStart && $0.date < prevEnd }
        return txs.flatMap(slices).filter { $0.amount < 0 }.reduce(0) { $0 - $1.amount }
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
                    .font(.headline.monospacedDigit()).foregroundStyle(color)
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
                    if loadingRecs { ProgressView() } else { Label("Refresh", systemImage: "arrow.clockwise") }
                }
                .disabled(loadingRecs || inRange.isEmpty)
                .accessibilityLabel("Refresh AI recommendations")
            }

            if let error { Text(error).foregroundStyle(.red).font(.caption) }

            if recs.filter({ !$0.dismissed }).isEmpty {
                EmptyState(text: "Tap refresh to ask the AI for ideas on cuts and savings.")
            } else {
                ForEach(recs.filter { !$0.dismissed }) { r in
                    RecommendationCard(rec: r, currency: base, theme: theme.current) {
                        r.dismissed = true
                        try? context.save()
                    }
                }
            }
        }
    }

    // MARK: - Computed series

    struct Daily: Identifiable { let id = UUID(); let date: Date; let expense: Decimal }
    struct CatTotal: Identifiable, Hashable {
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
        let weekday: Int
        let label: String
        let amount: Decimal
    }

    private var byDay: [Daily] {
        let cal = Calendar.current
        let txs = inRange.filter { $0.amount < 0 }
        let groups = Dictionary(grouping: txs) { cal.startOfDay(for: $0.date) }
        return groups
            .map { Daily(date: $0.key, expense: $0.value.reduce(Decimal(0)) { acc, tx in
                acc + -tx.amountInBase(base, liveConvert: convert)
            }) }
            .sorted { $0.date < $1.date }
    }

    private var byCategory: [CatTotal] {
        var totals: [String: Decimal] = [:]
        for tx in inRange {
            for slice in slices(tx) where slice.amount < 0 {
                let name = slice.category?.name ?? "Other"
                totals[name, default: 0] += -slice.amount
            }
        }
        return totals
            .map { CatTotal(name: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
            .prefix(10).map { $0 }
    }

    private var topPayees: [PayeeTotal] {
        let txs = inRange.filter { $0.amount < 0 }
        let groups = Dictionary(grouping: txs) { $0.payee }
        return groups.map { (key, items) in
            PayeeTotal(
                name: key,
                total: items.reduce(Decimal(0)) { $0 + -$1.amountInBase(base, liveConvert: convert) },
                count: items.count
            )
        }
        .sorted { $0.total > $1.total }
        .prefix(8).map { $0 }
    }

    private var byDow: [DowTotal] {
        let cal = Calendar.current
        let labels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        var totals: [Int: Decimal] = [:]
        for tx in inRange where tx.amount < 0 {
            let dow = cal.component(.weekday, from: tx.date)
            totals[dow, default: 0] += -tx.amountInBase(base, liveConvert: convert)
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
                context.insert(AIRecommendation(
                    kind: kind, title: w.title, body: w.body,
                    estimatedMonthlySavings: w.estimated_monthly_savings.map { Decimal($0) }
                ))
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
        s += "\n\nBy category (expenses, \(base)):\n"
        for c in byCategory.prefix(12) { s += "- \(c.name): \(c.amount)\n" }
        s += "\nTop merchants:\n"
        for p in topPayees { s += "- \(p.name): \(p.total) (\(p.count) tx)\n" }
        if !rules.isEmpty {
            s += "\nDetected subscriptions (monthly):\n"
            for r in rules.prefix(10) {
                let m = fx.convert(r.monthlyEstimate, from: r.currency, to: base)
                s += "- \(r.displayName): \(m) \(base) (\(r.cadence.displayName.lowercased()))\n"
            }
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
                .monospacedDigit().foregroundStyle(color)
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
        if isCount { return "\(NSDecimalNumber(decimal: value).intValue)" }
        if let currency { return CurrencyFormatter.string(for: value, currency: currency) }
        return "\(value)"
    }
}

private struct EmptyState: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.callout).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct SubscriptionRow: View {
    let rule: RecurringRule
    let base: String
    let fx: FXService
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.title2).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.displayName).font(.callout.bold())
                HStack(spacing: 6) {
                    Text(rule.cadence.displayName).foregroundStyle(.secondary)
                    if let c = rule.category {
                        Text("· \(c.name)").foregroundStyle(.secondary)
                    }
                    Text("· seen \(rule.occurrences)×").foregroundStyle(.tertiary)
                }
                .font(.caption)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                let monthlyBase = -fx.convert(rule.monthlyEstimate, from: rule.currency, to: base)
                Text(CurrencyFormatter.string(for: monthlyBase, currency: base))
                    .font(.callout.monospacedDigit()).foregroundStyle(.red)
                Text("/mo").font(.caption2).foregroundStyle(.secondary)
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .accessibilityLabel("Dismiss subscription")
        }
        .padding(.vertical, 8)
    }
}

private struct RecommendationCard: View {
    let rec: AIRecommendation
    let currency: String
    let theme: AppTheme
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
                        .font(.caption.bold()).foregroundStyle(theme.incomeColor)
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
        case .savings: theme.incomeColor
        case .general: theme.tint
        }
    }
}

private struct DrilldownSheet: View {
    let title: String
    let transactions: [Transaction]
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
                            .font(.headline.monospacedDigit()).foregroundStyle(.red)
                    }
                }
                Section("\(transactions.count) transaction\(transactions.count == 1 ? "" : "s")") {
                    ForEach(transactions.sorted { $0.date > $1.date }) { tx in
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
        transactions.reduce(Decimal(0)) { acc, tx in
            acc + (-tx.amountInBase(base) { fx.convert($0, from: $1, to: $2) })
        }
    }
}
