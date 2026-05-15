import Foundation

/// Generates the "What it could've been" comparisons surfaced on
/// Analytics. Pure-function: takes transactions + dreams + a
/// reference catalogue, returns a list of comparisons ranked by
/// how striking they are.
///
/// Two flavours:
///   - **Vice → Dream**: "Your €1,800 of alcohol = 36% of an
///     engagement ring." Negative framing, drives behaviour change.
///   - **Savings → Dream**: "Your €350/mo savings rate puts you
///     14 months from a mortgage deposit." Positive framing.
///
/// Vice pools are the same behavioural buckets analytics already
/// surfaces: alcohol, coffee, dining/fast food combined, brand-tax
/// premium spend, and Hall-of-Shame regrets. Each pool is summarised
/// as a monthly average over the last 3 months (so seasonal noise
/// doesn't flip the numbers wildly) plus a 12-month total for the
/// "if you kept this up for a year" framing.
enum CounterfactualEngine {

    typealias Converter = (Decimal, String, String) -> Decimal

    // MARK: - Pools

    struct VicePool: Identifiable, Hashable {
        let id: String
        let label: String
        let emoji: String
        /// Average monthly spend over the trailing 3 months in EUR.
        let monthlyEUR: Decimal
        /// Trailing 12 months total in EUR — used by the "annual"
        /// framing.
        let annualEUR: Decimal
    }

    static func vicePools(
        in transactions: [Transaction],
        base: String,
        convert: Converter,
        now: Date = .now
    ) -> [VicePool] {
        let cal = Calendar(identifier: .gregorian)
        guard let monthlyCutoff = cal.date(byAdding: .month, value: -3, to: now),
              let annualCutoff = cal.date(byAdding: .month, value: -12, to: now)
        else { return [] }

        // Slices keyed by pool id. Each transaction may fall into more
        // than one pool (a regret-flagged dining-out tx counts in both
        // dining and regrets); that's deliberate.
        var monthly: [String: Decimal] = [:]
        var annual: [String: Decimal] = [:]
        let labels: [(id: String, label: String, emoji: String)] = [
            ("alcohol",   "alcohol",          "🍻"),
            ("coffee",    "coffee runs",      "☕️"),
            ("dining",    "dining out",       "🍔"),
            ("brandtax",  "premium retail",   "🛍"),
            ("regret",    "Hall-of-Shame buys", "🤡")
        ]

        for tx in transactions where tx.amount < 0 {
            let inBase = -tx.amountInBase(base, liveConvert: convert)
            let buckets = bucketsFor(tx: tx)
            for bucket in buckets {
                if tx.date >= monthlyCutoff {
                    monthly[bucket, default: 0] += inBase
                }
                if tx.date >= annualCutoff {
                    annual[bucket, default: 0] += inBase
                }
            }
        }

        return labels.compactMap { entry -> VicePool? in
            let m = monthly[entry.id] ?? 0
            let a = annual[entry.id] ?? 0
            guard a > 0 else { return nil }
            return VicePool(
                id: entry.id, label: entry.label, emoji: entry.emoji,
                monthlyEUR: m / 3,   // 3-month avg → monthly
                annualEUR: a
            )
        }
    }

    /// All buckets this transaction contributes to. Centralised so the
    /// behavioural buckets stay in sync with `MerchantClassifier`.
    private static func bucketsFor(tx: Transaction) -> [String] {
        var buckets: [String] = []
        let catName = tx.category?.name.lowercased() ?? ""
        // Alcohol — category match wins, fall back to merchant heuristic.
        if catName == "alcohol"
            || MerchantClassifier.isAlcohol(payee: tx.payee, categoryName: tx.category?.name) {
            buckets.append("alcohol")
        }
        if MerchantClassifier.isCoffee(tx.payee) || catName == "coffee" {
            buckets.append("coffee")
        }
        if catName == "dining" || MerchantClassifier.isFastFood(tx.payee) {
            buckets.append("dining")
        }
        if MerchantClassifier.isPremiumRetail(tx.payee) {
            buckets.append("brandtax")
        }
        if tx.isRegret {
            buckets.append("regret")
        }
        return buckets
    }

    // MARK: - Targets

    /// A target a vice pool can be compared *against*. Either a
    /// user-defined dream or a built-in reference purchase.
    enum Target: Identifiable, Hashable {
        case dream(UserDream)
        case reference(ReferencePurchase)

        var id: String {
            switch self {
            case .dream(let d):       return "dream-\(d.id.uuidString)"
            case .reference(let r):   return "ref-\(r.id)"
            }
        }
        var name: String {
            switch self {
            case .dream(let d):       return d.name
            case .reference(let r):   return r.name
            }
        }
        var emoji: String {
            switch self {
            case .dream(let d):       return d.emoji
            case .reference(let r):   return r.emoji
            }
        }
        var priceEUR: Decimal {
            switch self {
            case .dream(let d):       return d.targetPrice
            case .reference(let r):   return r.price
            }
        }
        var isUserDream: Bool {
            if case .dream = self { return true }
            return false
        }

        func hash(into hasher: inout Hasher) { hasher.combine(id) }
        static func == (lhs: Target, rhs: Target) -> Bool { lhs.id == rhs.id }
    }

    // MARK: - Counterfactuals

    struct ViceComparison: Identifiable, Hashable {
        let id = UUID()
        let pool: VicePool
        let target: Target
        /// "Your €1,800 of alcohol this year would buy 1.6 weekends in Lisbon"
        let blurb: String
        /// Multiple of target the annual pool covers (0..∞).
        let multiplier: Double

        func hash(into hasher: inout Hasher) { hasher.combine(id) }
        static func == (lhs: ViceComparison, rhs: ViceComparison) -> Bool { lhs.id == rhs.id }
    }

    struct SavingsComparison: Identifiable, Hashable {
        let id = UUID()
        let target: Target
        let monthlySavingsEUR: Decimal
        /// Months to reach the target at the current savings rate.
        /// Always present — `savingsComparisons` early-returns when the
        /// rate is zero, so there is no nil case to model.
        let monthsToTarget: Int
        let blurb: String

        func hash(into hasher: inout Hasher) { hasher.combine(id) }
        static func == (lhs: SavingsComparison, rhs: SavingsComparison) -> Bool { lhs.id == rhs.id }
    }

    /// Build the negative-framed comparisons. Pair each vice pool with
    /// targets of roughly the right scale (lifestyle items for monthly
    /// pools, bigger items for annual / multi-year framing).
    static func viceComparisons(
        pools: [VicePool],
        dreams: [UserDream] = [],
        catalogue: [ReferencePurchase] = ReferencePurchase.all
    ) -> [ViceComparison] {
        // Convert user dreams to Targets, prefer them over the catalogue.
        let dreamTargets = dreams
            .filter { $0.achievedAt == nil && $0.targetPrice > 0 }
            .map(Target.dream)
        let refTargets = catalogue.map(Target.reference)
        let allTargets = dreamTargets + refTargets

        var out: [ViceComparison] = []
        for pool in pools where pool.annualEUR > 0 {
            // Pick the most striking ratio for this pool — typically the
            // first target whose price sits between 0.3× and 3× the
            // annual pool, so the number isn't comically tiny or huge.
            let scaled = allTargets
                .map { target -> (Target, Double) in
                    let mult = NSDecimalNumber(decimal: pool.annualEUR).doubleValue
                              / max(0.01, NSDecimalNumber(decimal: target.priceEUR).doubleValue)
                    return (target, mult)
                }
                .sorted { closenessToHero($0.1) < closenessToHero($1.1) }

            // Pick top 2 — one usually fits well, second one is for
            // rotation when the card cycles.
            for (target, mult) in scaled.prefix(2) {
                out.append(ViceComparison(
                    pool: pool,
                    target: target,
                    blurb: viceBlurb(pool: pool, target: target, multiplier: mult),
                    multiplier: mult
                ))
            }
        }
        return out
    }

    /// Build the positive-framed comparisons against the user's
    /// monthly net savings (income − expense).
    static func savingsComparisons(
        monthlySavingsEUR: Decimal,
        dreams: [UserDream] = [],
        catalogue: [ReferencePurchase] = ReferencePurchase.all
    ) -> [SavingsComparison] {
        guard monthlySavingsEUR > 0 else { return [] }
        let savings = NSDecimalNumber(decimal: monthlySavingsEUR).doubleValue

        let dreamTargets = dreams
            .filter { $0.achievedAt == nil && $0.targetPrice > 0 }
            .map(Target.dream)
        // For savings we lean on the bigger reference purchases —
        // "20 months to a mortgage deposit" reads better than "1
        // month to AirPods".
        let refTargets = catalogue
            .filter { $0.kind == .big || $0.kind == .biggest }
            .map(Target.reference)
        let allTargets = dreamTargets + refTargets

        return allTargets.map { target in
            let price = NSDecimalNumber(decimal: target.priceEUR).doubleValue
            let monthsToTarget = Int(ceil(price / savings))
            return SavingsComparison(
                target: target,
                monthlySavingsEUR: monthlySavingsEUR,
                monthsToTarget: monthsToTarget,
                blurb: savingsBlurb(monthsToTarget: monthsToTarget, target: target)
            )
        }.sorted { $0.monthsToTarget < $1.monthsToTarget }
    }

    // MARK: - Copy

    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "EUR"
        f.maximumFractionDigits = 0
        return f
    }()

    private static func viceBlurb(
        pool: VicePool,
        target: Target,
        multiplier mult: Double
    ) -> String {
        let amount = formatter.string(from: pool.annualEUR as NSDecimalNumber) ?? "€?"
        let multStr: String = {
            if mult >= 1.5 {
                return String(format: "%.1f×", mult)
            } else if mult >= 0.5 {
                return "\(Int((mult * 100).rounded()))% of"
            } else {
                return String(format: "%.1f×", mult)
            }
        }()
        let prefix = target.isUserDream ? "" : "≈ "
        return "Your \(amount) of \(pool.label) this year = \(prefix)\(multStr) \(target.name)."
    }

    private static func savingsBlurb(monthsToTarget: Int, target: Target) -> String {
        if monthsToTarget <= 3 {
            return "\(monthsToTarget) months from \(target.name) at your current pace."
        } else if monthsToTarget < 36 {
            return "About \(monthsToTarget) months from \(target.name) at your current savings rate."
        } else {
            let years = Double(monthsToTarget) / 12
            return String(format: "About %.1f years from \(target.name) at your current pace.", years)
        }
    }

    /// "Closeness to hero" — how interesting the multiplier is. We
    /// want something near 1.0×, ideally in the 0.5–2× band. Numbers
    /// like 0.02× or 50× read as either trivial or absurd.
    private static func closenessToHero(_ mult: Double) -> Double {
        // Penalty grows the further we are from the 1× sweet spot,
        // but on a log scale so 5× and 0.2× rate similarly.
        let log = log10(max(0.001, mult))
        return abs(log)
    }
}
