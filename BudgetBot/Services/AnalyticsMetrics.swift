import Foundation

/// Pure-function analytics. Takes a slice of transactions + a converter
/// closure for FX, returns the breakdowns the UI renders.
///
/// All methods accept already-filtered transactions (the caller decides
/// the date range) and an explicit base currency. The conversion closure
/// is injected rather than depending on FXService so the metrics are
/// straightforward to unit-test with a stub.
enum AnalyticsMetrics {

    typealias Converter = (Decimal, String, String) -> Decimal

    // MARK: - Need vs Want

    struct NeedVsWant: Equatable {
        let necessary: Decimal
        let discretionary: Decimal
        let regret: Decimal
        /// Total of all three buckets — convenience for ratio rendering.
        var total: Decimal { necessary + discretionary + regret }
    }

    /// Splits expenses into the three behavioural buckets defined by
    /// `CategoryClassifier`. A transaction flagged `isRegret` always counts
    /// toward `regret`, regardless of category — that's the whole point of
    /// the user marking it.
    static func needVsWant(
        in txs: [Transaction],
        base: String,
        convert: Converter
    ) -> NeedVsWant {
        var necessary: Decimal = 0
        var discretionary: Decimal = 0
        var regret: Decimal = 0

        for tx in txs where tx.amount < 0 {
            let slices = tx.categorisedSlices(in: base, liveConvert: convert)
            for slice in slices where slice.amount < 0 {
                let amt = -slice.amount
                if tx.isRegret {
                    regret += amt
                } else {
                    switch CategoryClassifier.bucket(forCategoryName: slice.category?.name) {
                    case .necessary:     necessary += amt
                    case .regret:        regret += amt
                    case .discretionary, .none: discretionary += amt
                    }
                }
            }
        }
        return NeedVsWant(necessary: necessary, discretionary: discretionary, regret: regret)
    }

    // MARK: - Regret / Dickhead Index

    struct RegretSummary: Equatable {
        let total: Decimal
        let count: Int
        /// Regret total as a fraction of total expenses (0...1).
        let shareOfTotalExpense: Double
        /// Worst single regret in the range, if any.
        let worstPayee: String?
        let worstAmount: Decimal?
    }

    static func regretSummary(
        in txs: [Transaction],
        base: String,
        convert: Converter
    ) -> RegretSummary {
        var total: Decimal = 0
        var count = 0
        var totalExpense: Decimal = 0
        var worst: (String, Decimal)? = nil

        for tx in txs where tx.amount < 0 {
            let inBase = -tx.amountInBase(base, liveConvert: convert)
            totalExpense += inBase
            if tx.isRegret {
                count += 1
                total += inBase
                if worst == nil || inBase > worst!.1 {
                    worst = (tx.payee, inBase)
                }
            }
        }
        let pct: Double = totalExpense == 0 ? 0
            : NSDecimalNumber(decimal: total).doubleValue
                / NSDecimalNumber(decimal: totalExpense).doubleValue
        return RegretSummary(
            total: total,
            count: count,
            shareOfTotalExpense: pct,
            worstPayee: worst?.0,
            worstAmount: worst?.1
        )
    }

    // MARK: - Value for money

    struct MerchantScore: Identifiable, Equatable {
        let id = UUID()
        let payee: String
        let visits: Int
        let total: Decimal
        let averagePerVisit: Decimal
        /// Composite score: higher = better value. Computed as
        /// `visits / averagePerVisit`. Frequent + cheap = "favourite";
        /// rare + expensive = "questionable". Bounded for display only,
        /// the raw ranking uses the unbounded value.
        let score: Double
    }

    /// Returns merchants split into "bang for buck" (top by score) and
    /// "questionable" (bottom by score). Requires at least 2 visits so a
    /// one-off big purchase doesn't dominate either list.
    static func merchantValue(
        in txs: [Transaction],
        base: String,
        convert: Converter,
        topK: Int = 5
    ) -> (best: [MerchantScore], questionable: [MerchantScore]) {
        let groups = Dictionary(grouping: txs.filter { $0.amount < 0 }) { $0.payee }
        let scored: [MerchantScore] = groups.compactMap { name, items in
            guard items.count >= 2 else { return nil }
            let total = items.reduce(Decimal(0)) { acc, tx in
                acc + -tx.amountInBase(base, liveConvert: convert)
            }
            let avg = total / Decimal(items.count)
            let avgDouble = max(0.01, NSDecimalNumber(decimal: avg).doubleValue)
            // visits / avg: more visits at a lower per-visit amount → higher
            // score. We multiply by 10 just to get human-readable numbers.
            let score = (Double(items.count) / avgDouble) * 10
            return MerchantScore(
                payee: name, visits: items.count, total: total,
                averagePerVisit: avg, score: score
            )
        }
        let bestFirst = scored.sorted { $0.score > $1.score }
        let worstFirst = scored.sorted { $0.score < $1.score }
        return (Array(bestFirst.prefix(topK)), Array(worstFirst.prefix(topK)))
    }

    // MARK: - Vice spending over time

    struct ViceWeek: Identifiable, Equatable {
        let id = UUID()
        let weekStart: Date
        let alcohol: Decimal
        let diningOut: Decimal
        let lateNight: Decimal
    }

    /// Per-week breakdown of "vice" spend — alcohol, dining out, and
    /// late-night purchases (any transaction between 22:00 and 04:00).
    static func viceByWeek(
        in txs: [Transaction],
        base: String,
        convert: Converter,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [ViceWeek] {
        var weeks: [Date: (alc: Decimal, dine: Decimal, late: Decimal)] = [:]
        for tx in txs where tx.amount < 0 {
            let weekStart = calendar.date(from:
                calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: tx.date)) ?? tx.date
            let inBase = -tx.amountInBase(base, liveConvert: convert)
            let hour = calendar.component(.hour, from: tx.date)
            let isLate = hour >= 22 || hour < 4
            var bucket = weeks[weekStart] ?? (0, 0, 0)
            let catName = tx.category?.name.lowercased() ?? ""
            if catName == "alcohol" { bucket.alc += inBase }
            if catName == "dining"  { bucket.dine += inBase }
            if isLate               { bucket.late += inBase }
            weeks[weekStart] = bucket
        }
        return weeks.map { ViceWeek(weekStart: $0.key, alcohol: $0.value.alc,
                                    diningOut: $0.value.dine, lateNight: $0.value.late) }
            .sorted { $0.weekStart < $1.weekStart }
    }

    // MARK: - Savings rate

    struct SavingsRate: Equatable {
        let income: Decimal
        let expense: Decimal
        let saved: Decimal
        /// 0..1, clamped. Negative if the user spent more than they earned.
        let rate: Double
    }

    static func savingsRate(
        in txs: [Transaction],
        base: String,
        convert: Converter
    ) -> SavingsRate {
        var income: Decimal = 0
        var expense: Decimal = 0
        for tx in txs {
            let inBase = tx.amountInBase(base, liveConvert: convert)
            if inBase > 0 { income += inBase } else { expense += -inBase }
        }
        let saved = income - expense
        let rate: Double = income == 0 ? 0
            : NSDecimalNumber(decimal: saved).doubleValue
                / NSDecimalNumber(decimal: income).doubleValue
        return SavingsRate(income: income, expense: expense, saved: saved, rate: rate)
    }

    // MARK: - Waste estimate

    struct WasteEstimate: Equatable {
        /// Regret transactions in the period.
        let regret: Decimal
        /// Monthly cost of subscriptions the user hasn't used in 60+ days
        /// according to `lastSeen`. Rough — surfaces stale auto-charges.
        let staleSubscriptions: Decimal
        var total: Decimal { regret + staleSubscriptions }
    }

    /// Estimate of "waste" — regrets in the range + cost of subscriptions
    /// not seen in 60 days. The subscription number is a monthly figure;
    /// the regret number is the period total. They're summed but the UI
    /// should label each separately so the user understands.
    static func wasteEstimate(
        in txs: [Transaction],
        rules: [RecurringRule],
        base: String,
        convert: Converter,
        now: Date = .now
    ) -> WasteEstimate {
        let regret = regretSummary(in: txs, base: base, convert: convert).total
        let staleCutoff = Calendar.current.date(byAdding: .day, value: -60, to: now) ?? now
        let stale = rules
            .filter { !$0.dismissed && $0.lastSeen < staleCutoff }
            .reduce(Decimal(0)) { acc, r in
                acc + (-convert(r.monthlyEstimate, r.currency, base))
            }
        return WasteEstimate(regret: regret, staleSubscriptions: stale)
    }

    // MARK: - The Drink Tab (alcohol + sober streaks)

    struct DrinkStats: Equatable {
        let totalSpent: Decimal
        /// Number of alcohol transactions in the range.
        let count: Int
        /// Longest run of consecutive days within the range without an
        /// alcohol transaction.
        let longestSoberStreakDays: Int
        /// Days since the last alcohol transaction up to `now`. `nil` if
        /// there were never any in the supplied range.
        let currentSoberStreakDays: Int?
        /// Mean spend per drinking *day* (multiple alcohol tx on one day
        /// count as a single drinking session for this metric).
        let avgPerSession: Decimal
        /// Most expensive single alcohol transaction's payee.
        let topPayee: String?
    }

    static func drinkStats(
        in txs: [Transaction],
        base: String,
        convert: Converter,
        now: Date = .now,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> DrinkStats {
        let alcohol = txs.filter { tx in
            tx.amount < 0 && MerchantClassifier.isAlcohol(
                payee: tx.payee, categoryName: tx.category?.name)
        }
        let total = alcohol.reduce(Decimal(0)) { acc, tx in
            acc + -tx.amountInBase(base, liveConvert: convert)
        }

        // Distinct days the user drank (for session math).
        let drinkingDays: Set<Date> = Set(alcohol.map {
            calendar.startOfDay(for: $0.date)
        })
        let avgPerSession: Decimal = drinkingDays.isEmpty
            ? 0
            : total / Decimal(drinkingDays.count)

        // Longest sober streak: scan the date range covered by `txs` and
        // count the largest gap (in days) between consecutive drinking
        // days. The range endpoints (earliest tx date / now) bound the
        // scan so a long stretch with no transactions at all still
        // contributes.
        let allDates = txs.map { calendar.startOfDay(for: $0.date) }.sorted()
        let rangeStart = allDates.first ?? calendar.startOfDay(for: now)
        let rangeEnd   = calendar.startOfDay(for: now)
        let sorted = drinkingDays.sorted()
        var longestGap = 0
        var previous = rangeStart
        for d in sorted {
            let gap = daysBetween(previous, and: d, in: calendar) - 1
            longestGap = max(longestGap, max(0, gap))
            previous = d
        }
        if let last = sorted.last {
            longestGap = max(longestGap, daysBetween(last, and: rangeEnd, in: calendar))
        } else if !allDates.isEmpty {
            longestGap = max(longestGap, daysBetween(rangeStart, and: rangeEnd, in: calendar))
        }

        let current: Int? = sorted.last.map { last in
            max(0, daysBetween(last, and: rangeEnd, in: calendar))
        }

        let top = alcohol.max(by: { lhs, rhs in
            -lhs.amountInBase(base, liveConvert: convert)
                < -rhs.amountInBase(base, liveConvert: convert)
        })?.payee

        return DrinkStats(
            totalSpent: total,
            count: alcohol.count,
            longestSoberStreakDays: longestGap,
            currentSoberStreakDays: current,
            avgPerSession: avgPerSession,
            topPayee: top
        )
    }

    // MARK: - Fast food / delivery

    struct FastFoodStats: Equatable {
        let totalSpent: Decimal
        let count: Int
        /// Days since the last fast-food / delivery transaction up to
        /// `now`. `nil` if there were never any in the range.
        let daysSinceLast: Int?
        /// Merchant that received the largest total fast-food spend.
        let topMerchant: String?
    }

    static func fastFoodStats(
        in txs: [Transaction],
        base: String,
        convert: Converter,
        now: Date = .now,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> FastFoodStats {
        let ff = txs.filter { $0.amount < 0 && MerchantClassifier.isFastFood($0.payee) }
        let total = ff.reduce(Decimal(0)) { acc, tx in
            acc + -tx.amountInBase(base, liveConvert: convert)
        }
        let lastDate = ff.map(\.date).max()
        let daysSince: Int? = lastDate.map {
            max(0, daysBetween(calendar.startOfDay(for: $0),
                               and: calendar.startOfDay(for: now),
                               in: calendar))
        }
        let byPayee = Dictionary(grouping: ff, by: \.payee)
            .mapValues { items in
                items.reduce(Decimal(0)) { acc, tx in
                    acc + -tx.amountInBase(base, liveConvert: convert)
                }
            }
        let topMerchant = byPayee.max { $0.value < $1.value }?.key
        return FastFoodStats(
            totalSpent: total, count: ff.count,
            daysSinceLast: daysSince, topMerchant: topMerchant
        )
    }

    // MARK: - Coffee

    struct CoffeeStats: Equatable {
        let totalSpent: Decimal
        let count: Int
        let avgPerCup: Decimal
        /// Spend extrapolated to a full year, holding the period rate
        /// constant. Useful as a "if you keep going at this rate"
        /// gut-punch.
        let annualisedCost: Decimal
        /// Counterfactual: same number of cups at €0.40 each (rough
        /// home-brew price). The difference between this and totalSpent
        /// is `homeBrewSavings`.
        let homeBrewCost: Decimal
        let homeBrewSavings: Decimal
        let favouriteCafé: String?
    }

    static func coffeeStats(
        in txs: [Transaction],
        base: String,
        convert: Converter,
        rangeDays: Int
    ) -> CoffeeStats {
        let coffee = txs.filter { $0.amount < 0 && MerchantClassifier.isCoffee($0.payee) }
        let total = coffee.reduce(Decimal(0)) { acc, tx in
            acc + -tx.amountInBase(base, liveConvert: convert)
        }
        let count = coffee.count
        let avg: Decimal = count == 0 ? 0 : total / Decimal(count)
        let safeRange = max(1, rangeDays)
        let annual = total * Decimal(365) / Decimal(safeRange)
        let homeBrew = Decimal(count) * Decimal(0.40)
        let savings  = max(0, total - homeBrew)

        let byCafé = Dictionary(grouping: coffee, by: \.payee)
            .mapValues { items in
                items.reduce(Decimal(0)) { acc, tx in
                    acc + -tx.amountInBase(base, liveConvert: convert)
                }
            }
        let fav = byCafé.max { $0.value < $1.value }?.key

        return CoffeeStats(
            totalSpent: total,
            count: count,
            avgPerCup: avg,
            annualisedCost: annual,
            homeBrewCost: homeBrew,
            homeBrewSavings: savings,
            favouriteCafé: fav
        )
    }

    // MARK: - Brand Tax (premium vs value retail)

    struct BrandTaxStats: Equatable {
        let premiumSpend: Decimal
        let valueSpend: Decimal
        /// Premium spend as a fraction of total *comparable* spend
        /// (premium + value). `nil` if neither bucket has activity.
        let premiumShare: Double?
        let topPremiumMerchant: String?
        /// Naïve estimate: if the premium spend had gone to a value
        /// retailer instead, assume a 30% discount on it. Surfaced as a
        /// "hypothetical" line.
        let estimatedSavingsAt30Off: Decimal
    }

    static func brandTax(
        in txs: [Transaction],
        base: String,
        convert: Converter
    ) -> BrandTaxStats {
        let premium = txs.filter {
            $0.amount < 0 && MerchantClassifier.isPremiumRetail($0.payee)
        }
        let value = txs.filter {
            $0.amount < 0 && MerchantClassifier.isValueRetail($0.payee)
        }
        let pSum = premium.reduce(Decimal(0)) { acc, tx in
            acc + -tx.amountInBase(base, liveConvert: convert)
        }
        let vSum = value.reduce(Decimal(0)) { acc, tx in
            acc + -tx.amountInBase(base, liveConvert: convert)
        }
        let comparable = pSum + vSum
        let share: Double? = comparable == 0 ? nil
            : NSDecimalNumber(decimal: pSum).doubleValue
                / NSDecimalNumber(decimal: comparable).doubleValue
        let topPremium = Dictionary(grouping: premium, by: \.payee)
            .mapValues { items in
                items.reduce(Decimal(0)) { acc, tx in
                    acc + -tx.amountInBase(base, liveConvert: convert)
                }
            }
            .max { $0.value < $1.value }?.key
        let savings = pSum * Decimal(0.30)
        return BrandTaxStats(
            premiumSpend: pSum,
            valueSpend: vSum,
            premiumShare: share,
            topPremiumMerchant: topPremium,
            estimatedSavingsAt30Off: savings
        )
    }

    // MARK: - Anomaly detection

    struct Anomaly: Identifiable, Equatable {
        let id = UUID()
        let transaction: Transaction
        /// Median absolute spend at this merchant across the comparison
        /// window. Provides context for the user — "you usually spend €X
        /// here, this was €Y."
        let typical: Decimal
        /// Multiple of typical that this transaction represents.
        let factor: Double

        static func == (lhs: Anomaly, rhs: Anomaly) -> Bool {
            lhs.transaction.id == rhs.transaction.id
        }
    }

    /// Flags transactions whose absolute amount is unusually high for the
    /// merchant. Heuristic: per-merchant median over the prior `window`
    /// days; flag anything in the most recent `recent` days where the
    /// amount is ≥ `factor` × median, requiring at least `minPriors`
    /// prior transactions so a single big buy can't define its own
    /// baseline.
    ///
    /// Returned anomalies are sorted by the headline-grabbing factor
    /// (biggest deviation first). Pure — no FX, no SwiftData calls
    /// inside the math.
    static func anomalies(
        in txs: [Transaction],
        base: String,
        convert: Converter,
        window: Int = 90,
        recent: Int = 14,
        factor: Double = 2.0,
        minPriors: Int = 3,
        now: Date = .now,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [Anomaly] {
        let recentCutoff = calendar.date(byAdding: .day, value: -recent, to: now) ?? now
        let windowCutoff = calendar.date(byAdding: .day, value: -window, to: now) ?? now

        // Group expense tx by payee inside the broader window.
        let expenses = txs.filter { $0.amount < 0 && $0.date >= windowCutoff }
        let grouped  = Dictionary(grouping: expenses) { $0.payee }

        var found: [Anomaly] = []
        for (_, items) in grouped {
            // Recent candidates: the spike we might flag.
            let recents = items.filter { $0.date >= recentCutoff }
            // Priors: everything strictly before the recent window.
            let priors  = items.filter { $0.date <  recentCutoff }
            guard priors.count >= minPriors else { continue }

            let priorAmounts: [Decimal] = priors.map { -$0.amountInBase(base, liveConvert: convert) }
            let med = median(priorAmounts)
            guard med > 0 else { continue }

            for tx in recents {
                let amt = -tx.amountInBase(base, liveConvert: convert)
                let f = NSDecimalNumber(decimal: amt).doubleValue
                      / NSDecimalNumber(decimal: med).doubleValue
                if f >= factor {
                    found.append(Anomaly(transaction: tx, typical: med, factor: f))
                }
            }
        }
        return found.sorted { $0.factor > $1.factor }
    }

    private static func median(_ values: [Decimal]) -> Decimal {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let n = sorted.count
        if n.isMultiple(of: 2) {
            return (sorted[n/2 - 1] + sorted[n/2]) / 2
        }
        return sorted[n/2]
    }

    // MARK: - Helpers

    private static func daysBetween(_ a: Date, and b: Date, in cal: Calendar) -> Int {
        cal.dateComponents([.day], from: a, to: b).day ?? 0
    }
}
