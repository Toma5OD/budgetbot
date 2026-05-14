import SwiftUI
import SwiftData
import Charts

/// Analytics screen. Aggregates via `Transaction.categorisedSlices(in:)`
/// so split transactions contribute per-split rows. Designed around
/// "show one premium metric per card, animate the reveal, expand drilldowns
/// in-place" — no modal sheets.
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
    @State private var selectedAngle: Double?
    @State private var appearAnimation = false
    @State private var lastSubscriptionScan: Date?

    // Inline drilldown state — replaces the old modal sheet. Tapping a
    // row, a donut wedge, or a bar sets one of these and reveals
    // transactions in place below the source.
    @State private var expandedCategory: String?
    @State private var expandedMerchant: String?
    @State private var expandedDay: Date?

    /// Per-category cut percentages driven by the Cut & Save sliders.
    /// Lives in the view because it's purely interactive — nothing is
    /// persisted; the savings number ticks live as the slider moves.
    @State private var cutPercents: [String: Double] = [:]

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

    private var base: String {
        profiles.first?.baseCurrency ?? profiles.first?.defaultCurrency ?? Currencies.localeDefault
    }
    private var palette: [Color] { theme.current.chartPalette }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    rangePicker
                    heroCard
                    summaryRow
                    streakChip
                    forecastCard
                    if let budget = profiles.first?.monthlyBudget, budget > 0, range == .month {
                        budgetCard(budget: budget)
                    }
                    needVsWantSection
                    flowChart
                    if regretSummary.count > 0 { dickheadSection }
                    categoryBreakdown
                    spinWheelSection
                    cutAndSaveSection
                    valueForMoneySection
                    topMerchants
                    viceTrackerSection
                    if savingsRate.income > 0 { savingsRateSection }
                    dayOfWeekChart
                    subscriptionsSection
                    wasteMeterSection
                    periodComparison
                    recommendationsSection
                }
                .padding()
                .animation(.snappy, value: range)
            }
            .navigationTitle("Analytics")
            .appHeaderToolbar()
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                    appearAnimation = true
                }
                rescanSubscriptionsIfNeeded()
            }
            .navigationDestination(for: Transaction.self) { tx in
                TransactionDetailView(tx: tx)
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

    // MARK: - Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Spent · \(range.rawValue.lowercased())")
                .font(.caption.bold())
                .tracking(0.6)
                .foregroundStyle(.secondary)

            AnimatedDecimal(
                target: expense,
                currency: base,
                font: .system(size: 44, weight: .black, design: theme.current.numericDesign),
                color: theme.current.expenseColor
            )
            .breathingPulse()

            HStack(spacing: 10) {
                deltaChip
                if hasIncome {
                    Label(
                        CurrencyFormatter.string(for: income, currency: base) + " in",
                        systemImage: "arrow.down.left.circle.fill"
                    )
                    .font(.caption.bold())
                    .foregroundStyle(theme.current.incomeColor)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .themedCard()
    }

    @ViewBuilder
    private var deltaChip: some View {
        if previousPeriodExpense > 0 {
            let diff = expense - previousPeriodExpense
            let pct = NSDecimalNumber(decimal: diff).doubleValue
                / NSDecimalNumber(decimal: previousPeriodExpense).doubleValue * 100
            let up = diff > 0
            let color: Color = up ? theme.current.expenseColor : theme.current.incomeColor
            Label("\(up ? "+" : "")\(Int(pct.rounded()))% vs prev",
                  systemImage: up ? "arrow.up.right" : "arrow.down.right")
                .font(.caption.bold())
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(color.opacity(0.15), in: Capsule())
                .foregroundStyle(color)
        }
    }

    // MARK: - Summary tile row

    private var summaryRow: some View {
        HStack(spacing: 10) {
            tile(title: "Transactions",
                 value: AnyView(AnimatedInt(target: inRange.count,
                                            font: .title3.bold().monospacedDigit(),
                                            color: theme.current.tint)),
                 tint: theme.current.tint)
            tile(title: "Avg/day",
                 value: AnyView(AnimatedDecimal(target: dailyAverage,
                                                currency: base,
                                                font: .title3.bold().monospacedDigit(),
                                                color: .primary)),
                 tint: .gray)
            if hasIncome {
                let net = income - expense
                tile(title: net >= 0 ? "Saved" : "Over",
                     value: AnyView(AnimatedDecimal(
                        target: abs(net), currency: base,
                        font: .title3.bold().monospacedDigit(),
                        color: net >= 0 ? theme.current.incomeColor : theme.current.expenseColor)),
                     tint: net >= 0 ? theme.current.incomeColor : theme.current.expenseColor)
            }
        }
    }

    @ViewBuilder
    private func tile(title: String, value: AnyView, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            value
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .themedCard()
    }

    // MARK: - Need vs Want

    private var needVsWantSection: some View {
        let split = AnalyticsMetrics.needVsWant(in: inRange, base: base, convert: convert)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Need vs want").font(.headline)
            if split.total == 0 {
                EmptyState(text: "No spend yet for this range.")
            } else {
                NeedVsWantBar(split: split, theme: theme.current, animate: appearAnimation)
                    .frame(height: 30)
                HStack(spacing: 18) {
                    legendDot(color: theme.current.tint,
                              label: "Necessary",
                              amount: split.necessary, currency: base, total: split.total)
                    legendDot(color: theme.current.chartPalette[1 % palette.count],
                              label: "Discretionary",
                              amount: split.discretionary, currency: base, total: split.total)
                    if split.regret > 0 {
                        legendDot(color: theme.current.expenseColor,
                                  label: "Vice",
                                  amount: split.regret, currency: base, total: split.total)
                    }
                }
                .font(.caption)
            }
        }
        .padding(16)
        .themedCard()
    }

    private func legendDot(color: Color, label: String,
                           amount: Decimal, currency: String, total: Decimal) -> some View {
        let pct: Double = total == 0 ? 0
            : NSDecimalNumber(decimal: amount).doubleValue
                / NSDecimalNumber(decimal: total).doubleValue * 100
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(label).foregroundStyle(.secondary)
            }
            Text("\(Int(pct.rounded()))% · \(CurrencyFormatter.string(for: amount, currency: currency))")
                .font(.caption.bold().monospacedDigit())
        }
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
                        y: .value("Amount",
                                  appearAnimation ? NSDecimalNumber(decimal: d.expense).doubleValue : 0)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [palette[d.paletteIndex % palette.count],
                                     palette[d.paletteIndex % palette.count].opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .cornerRadius(6)
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
                if let day = expandedDay {
                    inlineDrilldown(title: dayLabel(day),
                                    transactions: txs(forDay: day),
                                    onClose: { withAnimation { expandedDay = nil } })
                }
            }
        }
        .padding(16)
        .themedCard()
    }

    private func handleBarTap(location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) {
        let plotFrame = geo[proxy.plotAreaFrame]
        guard plotFrame.contains(location),
              let date: Date = proxy.value(atX: location.x - plotFrame.origin.x) else { return }
        let day = Calendar.current.startOfDay(for: date)
        let dayTxs = txs(forDay: day)
        guard !dayTxs.isEmpty else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
            expandedDay = expandedDay == day ? nil : day
            expandedCategory = nil
            expandedMerchant = nil
        }
    }

    private func txs(forDay day: Date) -> [Transaction] {
        inRange.filter { Calendar.current.isDate($0.date, inSameDayAs: day) && $0.amount < 0 }
    }

    private func dayLabel(_ day: Date) -> String {
        let df = DateFormatter(); df.dateStyle = .medium
        return df.string(from: day)
    }

    // MARK: - Dickhead Index

    private var dickheadSection: some View {
        let r = regretSummary
        return HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(theme.current.expenseColor.opacity(0.18), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: appearAnimation ? min(r.shareOfTotalExpense, 1) : 0)
                    .stroke(
                        AngularGradient(
                            colors: [theme.current.expenseColor, theme.current.expenseColor.opacity(0.55)],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.9, dampingFraction: 0.85), value: appearAnimation)
                Text("\(Int((r.shareOfTotalExpense * 100).rounded()))%")
                    .font(.title3.bold().monospacedDigit())
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text("Dickhead Index")
                    .font(.caption.bold())
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                AnimatedDecimal(
                    target: r.total,
                    currency: base,
                    font: .title2.bold().monospacedDigit(),
                    color: theme.current.expenseColor
                )
                if let worst = r.worstPayee, let amt = r.worstAmount {
                    Text("Worst: \(worst) · \(CurrencyFormatter.string(for: amt, currency: base))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text("\(r.count) Ls")
                .font(.caption.bold())
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(theme.current.expenseColor.opacity(0.15), in: Capsule())
                .foregroundStyle(theme.current.expenseColor)
        }
        .padding(16)
        .themedCard()
    }

    // MARK: - Category donut

    private var categoryBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Where it goes").font(.headline)
            if byCategory.isEmpty {
                EmptyState(text: "No expense data yet for this range.")
            } else {
                donut
                    .frame(height: 240)
                    .rotation3DEffect(
                        .degrees(selectedCategory == nil ? 0 : 12),
                        axis: (x: 1, y: 0, z: 0),
                        anchor: .center,
                        perspective: 0.45
                    )
                    .animation(.spring(response: 0.45, dampingFraction: 0.8), value: selectedCategory?.id)

                VStack(spacing: 0) {
                    ForEach(byCategory) { c in
                        categoryRow(c)
                        if c.id != byCategory.last?.id { Divider() }
                    }
                }
            }
        }
        .padding(16)
        .themedCard()
    }

    private var donut: some View {
        Chart(byCategory) { c in
            SectorMark(
                angle: .value("Amount",
                              appearAnimation ? NSDecimalNumber(decimal: c.amount).doubleValue : 0),
                innerRadius: .ratio(0.55),
                outerRadius: c.id == selectedCategory?.id ? .ratio(1.05) : .ratio(0.95),
                angularInset: 1.5
            )
            .cornerRadius(4)
            .foregroundStyle(colorFor(c))
            .opacity(selectedCategory == nil || selectedCategory?.id == c.id ? 1.0 : 0.32)
        }
        .chartAngleSelection(value: $selectedAngle)
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: appearAnimation)
        .animation(.spring(response: 0.4, dampingFraction: 0.78), value: selectedCategory?.id)
        .chartBackground { _ in
            VStack(spacing: 4) {
                if let sel = selectedCategory {
                    Text(sel.name).font(.subheadline.bold())
                    Text(CurrencyFormatter.string(for: sel.amount, currency: base))
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(theme.current.expenseColor)
                    let pct = NSDecimalNumber(decimal: sel.amount).doubleValue
                        / NSDecimalNumber(decimal: max(expense, 0.01)).doubleValue
                    Text("\(Int((pct * 100).rounded()))%")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Total").font(.caption).foregroundStyle(.secondary)
                    AnimatedDecimal(
                        target: expense, currency: base,
                        font: .title3.bold().monospacedDigit(),
                        color: .primary
                    )
                    Text("Tap a slice").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .transition(.scale.combined(with: .opacity))
        }
        .onChange(of: selectedAngle) { _, _ in
            if let cat = selectedCategory {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                    expandedCategory = expandedCategory == cat.name ? nil : cat.name
                    expandedMerchant = nil
                    expandedDay = nil
                }
                selectedAngle = nil
            }
        }
    }

    @ViewBuilder
    private func categoryRow(_ c: CatTotal) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                    expandedCategory = expandedCategory == c.name ? nil : c.name
                    expandedMerchant = nil
                    expandedDay = nil
                }
            } label: {
                HStack(spacing: 10) {
                    Circle().fill(colorFor(c)).frame(width: 12, height: 12)
                    Text(c.name).font(.callout)
                    Spacer()
                    Text(CurrencyFormatter.string(for: c.amount, currency: base))
                        .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    Image(systemName: expandedCategory == c.name ? "chevron.down" : "chevron.right")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .animation(.easeInOut, value: expandedCategory)
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            if expandedCategory == c.name {
                inlineDrilldown(title: c.name,
                                transactions: txs(forCategory: c.name),
                                onClose: { withAnimation { expandedCategory = nil } })
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

    private func txs(forCategory name: String) -> [Transaction] {
        inRange.filter { tx in
            slices(tx).contains { ($0.category?.name ?? "Other") == name && $0.amount < 0 }
        }
    }

    // MARK: - Value for money

    private var valueForMoneySection: some View {
        let (best, questionable) = AnalyticsMetrics.merchantValue(
            in: inRange, base: base, convert: convert)
        return VStack(alignment: .leading, spacing: 14) {
            Text("Value for money").font(.headline)
            if best.isEmpty && questionable.isEmpty {
                EmptyState(text: "Need a few repeat visits to score merchants. Capture more receipts first.")
            } else {
                if !best.isEmpty {
                    valueColumn(title: "Bang for your buck",
                                subtitle: "Cheap & frequent — friends",
                                tint: theme.current.incomeColor,
                                rows: best)
                }
                if !questionable.isEmpty {
                    valueColumn(title: "Questionable value",
                                subtitle: "Rare & pricey — squint at these",
                                tint: theme.current.expenseColor,
                                rows: questionable)
                }
            }
        }
        .padding(16)
        .themedCard()
    }

    @ViewBuilder
    private func valueColumn(title: String, subtitle: String, tint: Color,
                             rows: [AnalyticsMetrics.MerchantScore]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.subheadline.bold())
                Spacer()
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
            VStack(spacing: 6) {
                ForEach(rows) { row in
                    HStack(spacing: 10) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(tint)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.payee).font(.callout)
                            Text("\(row.visits)× · avg \(CurrencyFormatter.string(for: row.averagePerVisit, currency: base))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(CurrencyFormatter.string(for: row.total, currency: base))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
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
                        merchantRow(p)
                        if p.id != topPayees.last?.id { Divider() }
                    }
                }
            }
        }
        .padding(16)
        .themedCard()
    }

    @ViewBuilder
    private func merchantRow(_ p: PayeeTotal) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                    expandedMerchant = expandedMerchant == p.name ? nil : p.name
                    expandedCategory = nil
                    expandedDay = nil
                }
            } label: {
                HStack {
                    Text(p.name).font(.callout).lineLimit(1)
                    Spacer()
                    Text("\(p.count)×").font(.caption).foregroundStyle(.secondary)
                    Text(CurrencyFormatter.string(for: p.total, currency: base))
                        .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    Image(systemName: expandedMerchant == p.name ? "chevron.down" : "chevron.right")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            if expandedMerchant == p.name {
                inlineDrilldown(title: p.name,
                                transactions: inRange.filter { $0.payee == p.name && $0.amount < 0 },
                                onClose: { withAnimation { expandedMerchant = nil } })
            }
        }
    }

    // MARK: - Inline drilldown

    /// Replaces the old modal sheet. Drops into place beneath the source
    /// row with a 3D push-forward transition.
    @ViewBuilder
    private func inlineDrilldown(title: String, transactions txs: [Transaction],
                                 onClose: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.subheadline.bold())
                Spacer()
                Text("\(txs.count) tx · " +
                     CurrencyFormatter.string(for:
                        txs.reduce(Decimal(0)) { acc, tx in
                            acc + (-tx.amountInBase(base, liveConvert: convert))
                        }, currency: base))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)

            let sortedTop = txs.sorted { $0.date > $1.date }.prefix(8)
            VStack(spacing: 0) {
                ForEach(Array(sortedTop)) { tx in
                    NavigationLink(value: tx) {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(tx.payee).font(.callout).lineLimit(1)
                                Text(tx.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(CurrencyFormatter.string(for: tx.amount, currency: tx.currency))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.red)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                    }
                    .buttonStyle(.plain)
                    if tx.id != sortedTop.last?.id { Divider() }
                }
                if txs.count > 8 {
                    Text("+ \(txs.count - 8) more")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 6)
                }
            }
            .padding(.bottom, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.thinMaterial)
        )
        .padding(.top, 4)
        .transition(
            .asymmetric(
                insertion: .scale(scale: 0.92, anchor: .top).combined(with: .opacity),
                removal:   .scale(scale: 0.96, anchor: .top).combined(with: .opacity)
            )
        )
    }

    // MARK: - Vice tracker

    private var viceTrackerSection: some View {
        let weeks = AnalyticsMetrics.viceByWeek(in: inRange, base: base, convert: convert)
        let hasContent = weeks.contains { $0.alcohol + $0.diningOut + $0.lateNight > 0 }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Vice tracker").font(.headline)
                Spacer()
                Text("Alcohol · Dining · Late-night")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if !hasContent {
                EmptyState(text: "Tag a few dinners-out, drinks, or late-night orders and they'll trend here.")
            } else {
                Chart {
                    ForEach(weeks) { w in
                        if w.alcohol > 0 {
                            LineMark(
                                x: .value("Week", w.weekStart, unit: .weekOfYear),
                                y: .value("EUR", appearAnimation ? NSDecimalNumber(decimal: w.alcohol).doubleValue : 0),
                                series: .value("Series", "Alcohol")
                            )
                            .foregroundStyle(palette[5 % palette.count])
                            .interpolationMethod(.catmullRom)
                            .symbol(.circle)
                        }
                        if w.diningOut > 0 {
                            LineMark(
                                x: .value("Week", w.weekStart, unit: .weekOfYear),
                                y: .value("EUR", appearAnimation ? NSDecimalNumber(decimal: w.diningOut).doubleValue : 0),
                                series: .value("Series", "Dining")
                            )
                            .foregroundStyle(palette[0 % palette.count])
                            .interpolationMethod(.catmullRom)
                            .symbol(.diamond)
                        }
                        if w.lateNight > 0 {
                            LineMark(
                                x: .value("Week", w.weekStart, unit: .weekOfYear),
                                y: .value("EUR", appearAnimation ? NSDecimalNumber(decimal: w.lateNight).doubleValue : 0),
                                series: .value("Series", "Late-night")
                            )
                            .foregroundStyle(theme.current.expenseColor)
                            .interpolationMethod(.catmullRom)
                            .symbol(.square)
                        }
                    }
                }
                .frame(height: 160)
                .animation(.spring(response: 0.8, dampingFraction: 0.85), value: appearAnimation)
            }
        }
        .padding(16)
        .themedCard()
    }

    // MARK: - Savings rate gauge

    private var savingsRateSection: some View {
        let s = savingsRate
        let clamped = max(-1.0, min(1.0, s.rate))
        let positive = s.rate >= 0
        let absShown = appearAnimation ? min(abs(clamped), 1.0) : 0
        return HStack(spacing: 20) {
            ZStack {
                Circle().stroke(Color.gray.opacity(0.15), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: absShown)
                    .stroke(
                        AngularGradient(
                            colors: positive
                                ? [theme.current.incomeColor, theme.current.incomeColor.opacity(0.6)]
                                : [theme.current.expenseColor, theme.current.expenseColor.opacity(0.6)],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 1.0, dampingFraction: 0.85), value: appearAnimation)
                VStack(spacing: 0) {
                    Text("\(Int((s.rate * 100).rounded()))%")
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(positive ? theme.current.incomeColor : theme.current.expenseColor)
                    Text(positive ? "saved" : "over")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 110, height: 110)

            VStack(alignment: .leading, spacing: 6) {
                Text("Savings rate").font(.caption.bold()).tracking(0.5).foregroundStyle(.secondary)
                rateRow("In",   CurrencyFormatter.string(for: s.income, currency: base), color: theme.current.incomeColor)
                rateRow("Out",  CurrencyFormatter.string(for: s.expense, currency: base), color: theme.current.expenseColor)
                Divider().padding(.vertical, 2)
                rateRow(positive ? "Saved" : "Over",
                    CurrencyFormatter.string(for: abs(s.saved), currency: base),
                    color: positive ? theme.current.incomeColor : theme.current.expenseColor,
                    bold: true)
            }
            Spacer()
        }
        .padding(16)
        .themedCard()
    }

    private func rateRow(_ label: String, _ value: String, color: Color, bold: Bool = false) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font((bold ? Font.callout.bold() : Font.callout).monospacedDigit())
                .foregroundStyle(color)
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
                        y: .value("Amount",
                                  appearAnimation ? NSDecimalNumber(decimal: d.amount).doubleValue : 0)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [palette[(d.weekday - 1) % palette.count],
                                     palette[(d.weekday - 1) % palette.count].opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .cornerRadius(6)
                }
                .frame(height: 150)
                .animation(.spring(response: 0.7, dampingFraction: 0.85), value: appearAnimation)
            }
        }
        .padding(16)
        .themedCard()
    }

    // MARK: - Waste meter

    private var wasteMeterSection: some View {
        let w = AnalyticsMetrics.wasteEstimate(in: inRange, rules: rules, base: base, convert: convert)
        let visible = w.total > 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Waste meter").font(.headline)
                Spacer()
                if visible {
                    AnimatedDecimal(
                        target: w.total, currency: base,
                        font: .title3.bold().monospacedDigit(),
                        color: theme.current.expenseColor
                    )
                }
            }
            if !visible {
                EmptyState(text: "No waste detected. Either you're a saint or we don't have enough data yet.")
            } else {
                rateRow("Regrets (this period)",
                    CurrencyFormatter.string(for: w.regret, currency: base),
                    color: theme.current.expenseColor)
                rateRow("Stale subs (60d+ silent)/mo",
                    CurrencyFormatter.string(for: w.staleSubscriptions, currency: base),
                    color: theme.current.expenseColor)
            }
        }
        .padding(16)
        .themedCard()
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
        .padding(16)
        .themedCard()
    }

    private func rescanSubscriptionsIfNeeded() {
        let stale = lastSubscriptionScan == nil
            || Date().timeIntervalSince(lastSubscriptionScan!) > 6 * 3600
        if stale { rescanSubscriptions(force: false) }
    }

    private func rescanSubscriptions(force: Bool) {
        lastSubscriptionScan = Date()
        let snaps: [SubscriptionDetector.Snapshot] = transactions.map { tx in
            .init(id: tx.id, date: tx.date, payee: tx.payee, amount: tx.amount,
                  currency: tx.currency, categoryName: tx.category?.name)
        }
        let candidates = SubscriptionDetector().detect(in: snaps)
        let existingKeys = Set(rules.map {
            Self.ruleKey(payee: $0.payeePattern, cadence: $0.cadence, currency: $0.currency)
        })

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
        try? context.save()
    }

    static func ruleKey(payee: String, cadence: RecurringRule.Cadence, currency: String) -> String {
        "\(payee)__\(cadence.rawValue)__\(currency)"
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
        .padding(16)
        .themedCard()
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
    private func comparisonCard(title: String, value: Decimal? = nil,
                                valueString: String? = nil, color: Color) -> some View {
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
                .font(.caption)
                .foregroundStyle(pct > 1.0 ? theme.current.expenseColor : .secondary)
        }
        .padding(16)
        .themedCard()
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
        .padding(16)
        .themedCard()
    }

    // MARK: - Streak chip

    /// Days in the range under the daily average. Cheap motivator —
    /// shown as a flame chip so it feels like a Duolingo streak.
    private var streakChip: some View {
        let avg = dailyAverage
        let goodDays = byDay.filter { $0.expense > 0 && $0.expense <= avg }.count
        let totalDaysWithSpend = byDay.filter { $0.expense > 0 }.count
        let pct: Double = totalDaysWithSpend == 0 ? 0
            : Double(goodDays) / Double(totalDaysWithSpend)
        let visible = totalDaysWithSpend >= 5
        return Group {
            if visible {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [.orange, .red.opacity(0.85)],
                                startPoint: .top, endPoint: .bottom))
                            .frame(width: 44, height: 44)
                        Text("🔥").font(.title2)
                    }
                    .breathingPulse(amplitude: 0.04, period: 2.4)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            AnimatedInt(target: goodDays,
                                        font: .title3.bold().monospacedDigit())
                            Text("/ \(totalDaysWithSpend) days under avg")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Text("\(Int((pct * 100).rounded()))% of spending days were chilled out")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .padding(14)
                .themedCard()
            }
        }
    }

    // MARK: - Forecast

    /// Projects end-of-month spend at the current run-rate. Only shows
    /// when range == .month so the linear projection makes sense.
    @ViewBuilder
    private var forecastCard: some View {
        if range == .month {
            let cal = Calendar.current
            let now = Date()
            let daysSoFar = max(1, cal.component(.day, from: now))
            let daysInMonth = cal.range(of: .day, in: .month, for: now)?.count ?? 30
            let perDay = expense / Decimal(daysSoFar)
            let projected = perDay * Decimal(daysInMonth)
            let budget = profiles.first?.monthlyBudget ?? 0
            let overBudget = budget > 0 && projected > budget

            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Color.gray.opacity(0.18), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: appearAnimation ? min(Double(daysSoFar)/Double(daysInMonth), 1) : 0)
                        .stroke(
                            LinearGradient(colors: [theme.current.tint, theme.current.tint.opacity(0.55)],
                                           startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 1.0, dampingFraction: 0.85), value: appearAnimation)
                    Text("\(daysSoFar)/\(daysInMonth)")
                        .font(.caption2.bold().monospacedDigit())
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Month-end forecast")
                        .font(.caption.bold())
                        .tracking(0.5)
                        .foregroundStyle(.secondary)
                    AnimatedDecimal(
                        target: projected, currency: base,
                        font: .title2.bold().monospacedDigit(),
                        color: overBudget ? theme.current.expenseColor : .primary
                    )
                    if budget > 0 {
                        Text(overBudget
                             ? "≈ \(CurrencyFormatter.string(for: projected - budget, currency: base)) over budget"
                             : "≈ \(CurrencyFormatter.string(for: budget - projected, currency: base)) under budget")
                            .font(.caption2)
                            .foregroundStyle(overBudget ? theme.current.expenseColor : theme.current.incomeColor)
                    } else {
                        Text("at current run-rate")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(14)
            .themedCard()
        }
    }

    // MARK: - Spin Wheel

    private var spinWheelSection: some View {
        let palette = theme.current.chartPalette
        let wedges: [SpinTheBudgetWheel.Wedge] = byCategory.enumerated().map { idx, c in
            SpinTheBudgetWheel.Wedge(
                label: c.name,
                amount: c.amount,
                color: palette[idx % palette.count]
            )
        }
        return SpinTheBudgetWheel(wedges: wedges, currency: base, theme: theme.current)
    }

    // MARK: - Cut & Save

    /// Interactive sliders: drag to hypothetically cut a category by X%
    /// and watch a running total tick up live. Pure fun-with-numbers,
    /// no persistence.
    private var cutAndSaveSection: some View {
        let top = Array(byCategory.prefix(5))
        let savings: Decimal = top.reduce(Decimal(0)) { acc, c in
            let pct = cutPercents[c.name] ?? 0
            return acc + (c.amount * Decimal(pct / 100))
        }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Cut & save").font(.headline)
                Spacer()
                if savings > 0 {
                    Text("save")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    AnimatedDecimal(
                        target: savings, currency: base,
                        font: .title3.bold().monospacedDigit(),
                        color: theme.current.incomeColor,
                        duration: 0.5
                    )
                }
            }
            if top.isEmpty {
                EmptyState(text: "Capture a few receipts first — sliders need categories to play with.")
            } else {
                VStack(spacing: 14) {
                    ForEach(top) { c in
                        cutRow(c)
                    }
                }
                if savings > 0 {
                    Text("Hypothetical. We're not actually cancelling Netflix — yet.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(16)
        .themedCard()
    }

    @ViewBuilder
    private func cutRow(_ c: CatTotal) -> some View {
        let pct = cutPercents[c.name] ?? 0
        let saved = c.amount * Decimal(pct / 100)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle().fill(colorFor(c)).frame(width: 8, height: 8)
                Text(c.name).font(.callout)
                Spacer()
                Text("\(Int(pct.rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("→ \(CurrencyFormatter.string(for: saved, currency: base))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(theme.current.incomeColor)
            }
            Slider(
                value: Binding(
                    get: { cutPercents[c.name] ?? 0 },
                    set: { new in cutPercents[c.name] = new }
                ),
                in: 0...100, step: 5
            )
            .tint(colorFor(c))
        }
    }

    // MARK: - Aggregations

    private func bounds() -> (Date, Date) {
        switch range {
        case .custom:
            let s = Calendar.current.startOfDay(for: customStart)
            let e = Calendar.current.date(byAdding: .day, value: 1,
                                          to: Calendar.current.startOfDay(for: customEnd)) ?? customEnd
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
    private var dailyAverage: Decimal {
        expense / Decimal(max(1, daysInRange))
    }
    private var daysInRange: Int {
        let (s, e) = bounds()
        return max(1, Calendar.current.dateComponents([.day], from: s, to: e).day ?? 1)
    }

    private var regretSummary: AnalyticsMetrics.RegretSummary {
        AnalyticsMetrics.regretSummary(in: inRange, base: base, convert: convert)
    }
    private var savingsRate: AnalyticsMetrics.SavingsRate {
        AnalyticsMetrics.savingsRate(in: inRange, base: base, convert: convert)
    }

    // MARK: - Computed series

    struct Daily: Identifiable {
        let id = UUID()
        let date: Date
        let expense: Decimal
        /// Stable index into the chart palette so each bar reads as a
        /// different colour and the chart doesn't look monochrome.
        let paletteIndex: Int
    }
    struct CatTotal: Identifiable, Hashable {
        let id = UUID(); let name: String; let amount: Decimal
    }
    struct PayeeTotal: Identifiable {
        let id = UUID(); let name: String; let total: Decimal; let count: Int
    }
    struct DowTotal: Identifiable {
        let id = UUID(); let weekday: Int; let label: String; let amount: Decimal
    }

    private var byDay: [Daily] {
        let cal = Calendar.current
        let txs = inRange.filter { $0.amount < 0 }
        let groups = Dictionary(grouping: txs) { cal.startOfDay(for: $0.date) }
        let unsorted = groups.map { (key: Date, value: [Transaction]) -> (Date, Decimal) in
            let total = value.reduce(Decimal(0)) { acc, tx in
                acc + -tx.amountInBase(base, liveConvert: convert)
            }
            return (key, total)
        }.sorted { $0.0 < $1.0 }
        return unsorted.enumerated().map { idx, pair in
            Daily(date: pair.0, expense: pair.1, paletteIndex: idx)
        }
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

    // MARK: - AI recommendations

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

// MARK: - Need vs Want segmented bar

private struct NeedVsWantBar: View {
    let split: AnalyticsMetrics.NeedVsWant
    let theme: Theme
    let animate: Bool

    var body: some View {
        GeometryReader { geo in
            let total = NSDecimalNumber(decimal: split.total).doubleValue
            let widthsRaw: [(Color, Double)] = [
                (theme.tint,                 NSDecimalNumber(decimal: split.necessary).doubleValue),
                (theme.chartPalette[1 % theme.chartPalette.count],
                                             NSDecimalNumber(decimal: split.discretionary).doubleValue),
                (theme.expenseColor,         NSDecimalNumber(decimal: split.regret).doubleValue)
            ]
            let widths = widthsRaw.map { ($0.0, max(0, $0.1) / max(total, 0.01)) }
            HStack(spacing: 2) {
                ForEach(Array(widths.enumerated()), id: \.offset) { _, item in
                    let (color, frac) = item
                    if frac > 0 {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [color, color.opacity(0.7)],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .frame(width: animate ? geo.size.width * frac : 0)
                    }
                }
                Spacer(minLength: 0)
            }
            .animation(.spring(response: 0.85, dampingFraction: 0.85), value: animate)
        }
    }
}

// MARK: - Subviews

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
    let theme: Theme
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
