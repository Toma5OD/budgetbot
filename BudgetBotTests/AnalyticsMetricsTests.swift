import XCTest
import SwiftData
@testable import BudgetBot

@MainActor
final class AnalyticsMetricsTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        try PersistenceController.makeInMemory()
    }

    private let identityConvert: AnalyticsMetrics.Converter = { amt, _, _ in amt }

    private func makeCategory(_ ctx: ModelContext, _ name: String,
                              _ kind: CategoryKind = .expense) -> TxCategory {
        let c = TxCategory(name: name, kind: kind)
        ctx.insert(c)
        return c
    }

    private func makeTx(_ ctx: ModelContext,
                        amount: Decimal,
                        payee: String,
                        date: Date = .now,
                        category: TxCategory? = nil,
                        isRegret: Bool = false) -> Transaction {
        let tx = Transaction(
            date: date, amount: amount, currency: "EUR",
            payee: payee, confirmed: true,
            isRegret: isRegret,
            category: category
        )
        ctx.insert(tx)
        return tx
    }

    // MARK: - Need vs Want

    func test_needVsWant_splitsByCategoryBucket() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let rent      = makeCategory(ctx, "Rent")
        let dining    = makeCategory(ctx, "Dining")
        let alcohol   = makeCategory(ctx, "Alcohol")

        _ = makeTx(ctx, amount: -1000, payee: "Landlord", category: rent)
        _ = makeTx(ctx, amount: -50,   payee: "Bunsen",   category: dining)
        _ = makeTx(ctx, amount: -30,   payee: "Pub",      category: alcohol)

        let split = AnalyticsMetrics.needVsWant(
            in: [Transaction](try ctx.fetch(FetchDescriptor<Transaction>())),
            base: "EUR", convert: identityConvert)

        XCTAssertEqual(split.necessary,     1000)
        XCTAssertEqual(split.discretionary, 50)
        XCTAssertEqual(split.regret,        30)
    }

    func test_needVsWant_regretFlaggedTxAlwaysCountsAsRegret() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let dining = makeCategory(ctx, "Dining")
        // A dining transaction that's been Hall-of-Shame flagged.
        _ = makeTx(ctx, amount: -38, payee: "Domino's 3am", category: dining, isRegret: true)

        let split = AnalyticsMetrics.needVsWant(
            in: try ctx.fetch(FetchDescriptor<Transaction>()),
            base: "EUR", convert: identityConvert)

        XCTAssertEqual(split.regret, 38)
        XCTAssertEqual(split.discretionary, 0,
                       "Marking dining as a regret should pull it out of discretionary")
    }

    // MARK: - Regret summary

    func test_regretSummary_findsWorstAndShare() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let cat = makeCategory(ctx, "Shopping")
        _ = makeTx(ctx, amount: -100, payee: "Groceries", category: cat)   // not regret
        _ = makeTx(ctx, amount: -30,  payee: "Late pizza",  category: cat, isRegret: true)
        _ = makeTx(ctx, amount: -127, payee: "Air-fryer",   category: cat, isRegret: true)

        let r = AnalyticsMetrics.regretSummary(
            in: try ctx.fetch(FetchDescriptor<Transaction>()),
            base: "EUR", convert: identityConvert)

        XCTAssertEqual(r.count, 2)
        XCTAssertEqual(r.total, 157)
        XCTAssertEqual(r.worstPayee, "Air-fryer")
        XCTAssertEqual(r.worstAmount, 127)
        // 157 / 257 ≈ 0.611
        XCTAssertEqual(r.shareOfTotalExpense, 157.0 / 257.0, accuracy: 0.001)
    }

    func test_regretSummary_zeroWhenNoneFlagged() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        _ = makeTx(ctx, amount: -10, payee: "Anything")

        let r = AnalyticsMetrics.regretSummary(
            in: try ctx.fetch(FetchDescriptor<Transaction>()),
            base: "EUR", convert: identityConvert)
        XCTAssertEqual(r.count, 0)
        XCTAssertEqual(r.total, 0)
        XCTAssertNil(r.worstPayee)
    }

    // MARK: - Merchant value

    func test_merchantValue_rankFrequentAndCheapAsBest() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        // Cheap & frequent — should top "best".
        for _ in 0..<10 { _ = makeTx(ctx, amount: -3, payee: "Coffee Spot") }
        // Rare & expensive — should top "questionable".
        for _ in 0..<2 { _ = makeTx(ctx, amount: -160, payee: "Pricey Bistro") }
        // Single visit — filtered out (need ≥ 2 visits).
        _ = makeTx(ctx, amount: -10, payee: "Once Off Place")

        let (best, questionable) = AnalyticsMetrics.merchantValue(
            in: try ctx.fetch(FetchDescriptor<Transaction>()),
            base: "EUR", convert: identityConvert)

        XCTAssertEqual(best.first?.payee, "Coffee Spot")
        XCTAssertEqual(questionable.first?.payee, "Pricey Bistro")
        XCTAssertFalse(best.contains { $0.payee == "Once Off Place" },
                       "Single-visit merchants are excluded so a one-off doesn't skew either list")
    }

    // MARK: - Savings rate

    func test_savingsRate_positiveWhenIncomeBeatsExpense() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        _ = makeTx(ctx, amount: 3000, payee: "Salary")
        _ = makeTx(ctx, amount: -1200, payee: "Rent")

        let s = AnalyticsMetrics.savingsRate(
            in: try ctx.fetch(FetchDescriptor<Transaction>()),
            base: "EUR", convert: identityConvert)

        XCTAssertEqual(s.income,  3000)
        XCTAssertEqual(s.expense, 1200)
        XCTAssertEqual(s.saved,   1800)
        XCTAssertEqual(s.rate, 0.6, accuracy: 0.0001)
    }

    func test_savingsRate_negativeWhenOverspending() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        _ = makeTx(ctx, amount: 1000,  payee: "Salary")
        _ = makeTx(ctx, amount: -1500, payee: "Holiday")

        let s = AnalyticsMetrics.savingsRate(
            in: try ctx.fetch(FetchDescriptor<Transaction>()),
            base: "EUR", convert: identityConvert)
        XCTAssertEqual(s.rate, -0.5, accuracy: 0.0001)
    }

    func test_savingsRate_zeroIncomeReturnsZero() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        _ = makeTx(ctx, amount: -50, payee: "X")
        let s = AnalyticsMetrics.savingsRate(
            in: try ctx.fetch(FetchDescriptor<Transaction>()),
            base: "EUR", convert: identityConvert)
        XCTAssertEqual(s.rate, 0)
    }

    // MARK: - Waste estimate

    // MARK: - Drink stats (alcohol + sober streak)

    func test_drinkStats_currentStreakIsDaysSinceLastAlcoholTx() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let alcohol = makeCategory(ctx, "Alcohol")
        let now = ISO8601DateFormatter().date(from: "2026-05-14T12:00:00Z")!
        let cal = Calendar(identifier: .gregorian)

        // Last drink 10 days ago.
        _ = makeTx(ctx, amount: -38, payee: "The Long Hall",
                   date: cal.date(byAdding: .day, value: -10, to: now)!,
                   category: alcohol)

        let s = AnalyticsMetrics.drinkStats(
            in: try ctx.fetch(FetchDescriptor<Transaction>()),
            base: "EUR", convert: identityConvert,
            now: now, calendar: cal)

        XCTAssertEqual(s.currentSoberStreakDays, 10)
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s.totalSpent, 38)
    }

    func test_drinkStats_longestStreakSpansBetweenSessions() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let alcohol = makeCategory(ctx, "Alcohol")
        let now = ISO8601DateFormatter().date(from: "2026-05-14T12:00:00Z")!
        let cal = Calendar(identifier: .gregorian)

        // Two drinks: 30 days ago and 5 days ago → longest gap is the
        // 24-day stretch in between (gap = 25 - 1 = 24 days sober).
        _ = makeTx(ctx, amount: -20, payee: "Mulligan",
                   date: cal.date(byAdding: .day, value: -30, to: now)!,
                   category: alcohol)
        _ = makeTx(ctx, amount: -25, payee: "Eight Degrees Brewing — Taproom",
                   date: cal.date(byAdding: .day, value: -5, to: now)!,
                   category: alcohol)
        // Plus an unrelated tx so the range starts further back.
        _ = makeTx(ctx, amount: -10, payee: "Boots",
                   date: cal.date(byAdding: .day, value: -40, to: now)!)

        let s = AnalyticsMetrics.drinkStats(
            in: try ctx.fetch(FetchDescriptor<Transaction>()),
            base: "EUR", convert: identityConvert,
            now: now, calendar: cal)

        XCTAssertGreaterThanOrEqual(s.longestSoberStreakDays, 24)
        XCTAssertEqual(s.currentSoberStreakDays, 5)
    }

    func test_drinkStats_noAlcoholReturnsZerosAndNilStreak() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        _ = makeTx(ctx, amount: -10, payee: "Tesco")
        let s = AnalyticsMetrics.drinkStats(
            in: try ctx.fetch(FetchDescriptor<Transaction>()),
            base: "EUR", convert: identityConvert)
        XCTAssertEqual(s.totalSpent, 0)
        XCTAssertEqual(s.count, 0)
        XCTAssertNil(s.currentSoberStreakDays)
    }

    // MARK: - Fast food stats

    func test_fastFoodStats_classifiesDeliveryAndChainsButNotSitDown() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let now = ISO8601DateFormatter().date(from: "2026-05-14T12:00:00Z")!
        let cal = Calendar(identifier: .gregorian)

        _ = makeTx(ctx, amount: -38, payee: "Domino's Pizza — Camden St",
                   date: cal.date(byAdding: .day, value: -2, to: now)!)
        _ = makeTx(ctx, amount: -12, payee: "Deliveroo",
                   date: cal.date(byAdding: .day, value: -6, to: now)!)
        // Sit-down restaurant — must NOT count as fast food.
        _ = makeTx(ctx, amount: -54, payee: "Manifesto Rathmines")

        let s = AnalyticsMetrics.fastFoodStats(
            in: try ctx.fetch(FetchDescriptor<Transaction>()),
            base: "EUR", convert: identityConvert,
            now: now, calendar: cal)

        XCTAssertEqual(s.count, 2,
                       "Manifesto is a sit-down restaurant, not fast food")
        XCTAssertEqual(s.totalSpent, 50)
        XCTAssertEqual(s.daysSinceLast, 2)
        XCTAssertEqual(s.topMerchant, "Domino's Pizza — Camden St")
    }

    // MARK: - Coffee stats

    func test_coffeeStats_annualisesAndComputesHomeBrewSavings() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // 10 cups at €4 each over 30 days.
        for _ in 0..<10 {
            _ = makeTx(ctx, amount: -4, payee: "Insomnia")
        }
        let s = AnalyticsMetrics.coffeeStats(
            in: try ctx.fetch(FetchDescriptor<Transaction>()),
            base: "EUR", convert: identityConvert, rangeDays: 30)

        XCTAssertEqual(s.count, 10)
        XCTAssertEqual(s.totalSpent, 40)
        XCTAssertEqual(s.avgPerCup, 4)
        // 40 * 365 / 30 ≈ 486.67
        let annual = NSDecimalNumber(decimal: s.annualisedCost).doubleValue
        XCTAssertEqual(annual, 486.67, accuracy: 0.5)
        // Home brew @ €0.40 × 10 = €4 → saving of €36.
        XCTAssertEqual(s.homeBrewSavings, 36)
        XCTAssertEqual(s.favouriteCafé, "Insomnia")
    }

    // MARK: - Brand tax

    func test_brandTax_shareAndSavingsEstimate() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        _ = makeTx(ctx, amount: -100, payee: "Brown Thomas Online")
        _ = makeTx(ctx, amount: -50,  payee: "Marks & Spencer Grafton")
        _ = makeTx(ctx, amount: -50,  payee: "Lidl Phibsboro")

        let s = AnalyticsMetrics.brandTax(
            in: try ctx.fetch(FetchDescriptor<Transaction>()),
            base: "EUR", convert: identityConvert)

        XCTAssertEqual(s.premiumSpend, 150)
        XCTAssertEqual(s.valueSpend, 50)
        XCTAssertEqual(s.premiumShare ?? 0, 0.75, accuracy: 0.001)
        XCTAssertEqual(s.topPremiumMerchant, "Brown Thomas Online")
        // 30% of 150 = 45
        XCTAssertEqual(s.estimatedSavingsAt30Off, 45)
    }

    func test_brandTax_returnsNilShareWhenNoComparableSpend() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        _ = makeTx(ctx, amount: -10, payee: "Random Corner Shop")
        let s = AnalyticsMetrics.brandTax(
            in: try ctx.fetch(FetchDescriptor<Transaction>()),
            base: "EUR", convert: identityConvert)
        XCTAssertNil(s.premiumShare)
    }

    func test_wasteEstimate_combinesRegretsAndStaleSubs() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        _ = makeTx(ctx, amount: -50, payee: "regrettable", isRegret: true)
        let recent = RecurringRule(
            payeePattern: "spotify", displayName: "Spotify",
            expectedAmount: -10, currency: "EUR", cadence: .monthly,
            firstSeen: .now, lastSeen: .now, occurrences: 5)
        let stale = RecurringRule(
            payeePattern: "ghost",  displayName: "Old gym membership",
            expectedAmount: -40, currency: "EUR", cadence: .monthly,
            firstSeen: .distantPast,
            lastSeen: Calendar.current.date(byAdding: .day, value: -120, to: .now)!,
            occurrences: 8)
        ctx.insert(recent); ctx.insert(stale)

        let w = AnalyticsMetrics.wasteEstimate(
            in: try ctx.fetch(FetchDescriptor<Transaction>()),
            rules: [recent, stale],
            base: "EUR", convert: identityConvert)

        XCTAssertEqual(w.regret, 50)
        XCTAssertEqual(w.staleSubscriptions, 40,
                       "Only the gym sub (60d+ silent) counts as stale")
        XCTAssertEqual(w.total, 90)
    }
}
