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
