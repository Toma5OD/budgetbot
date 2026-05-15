import XCTest
import SwiftData
@testable import BudgetBot

@MainActor
final class HindsightBreakdownTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        try PersistenceController.makeInMemory()
    }

    private let identityConvert: AnalyticsMetrics.Converter = { amt, _, _ in amt }

    private func cat(_ ctx: ModelContext, _ name: String) -> TxCategory {
        let c = TxCategory(name: name, kind: .expense)
        ctx.insert(c)
        return c
    }

    private func tx(_ ctx: ModelContext, amount: Decimal, payee: String,
                    rating: Int? = nil, category: TxCategory? = nil) -> Transaction {
        let t = Transaction(
            amount: amount, currency: "EUR", payee: payee, confirmed: true,
            hindsightRating: rating,
            hindsightRatedAt: rating == nil ? nil : .now,
            category: category
        )
        ctx.insert(t)
        return t
    }

    func test_breakdown_skipsUnratedAndIncome() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let dining = cat(ctx, "Dining")

        _ = tx(ctx, amount: -20, payee: "Bunsen", rating: 3, category: dining)
        _ = tx(ctx, amount: -15, payee: "Tesco")                              // unrated
        _ = tx(ctx, amount: 1000, payee: "Salary", rating: 5)                 // income — excluded

        let h = AnalyticsMetrics.hindsightBreakdown(
            in: try ctx.fetch(FetchDescriptor<Transaction>()),
            base: "EUR", convert: identityConvert)

        XCTAssertEqual(h.ratedCount, 1, "Only the rated expense counts")
        XCTAssertEqual(h.unratedCount, 1)
        XCTAssertEqual(h.totalRatedSpend, 20)
    }

    func test_breakdown_splitsLowAndHighRatedSpend() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        _ = tx(ctx, amount: -50,  payee: "Domino's",  rating: 1)
        _ = tx(ctx, amount: -30,  payee: "ASOS",      rating: 2)
        _ = tx(ctx, amount: -25,  payee: "Tesco",     rating: 3)
        _ = tx(ctx, amount: -40,  payee: "Manifesto", rating: 4)
        _ = tx(ctx, amount: -120, payee: "Aer Lingus", rating: 5)

        let h = AnalyticsMetrics.hindsightBreakdown(
            in: try ctx.fetch(FetchDescriptor<Transaction>()),
            base: "EUR", convert: identityConvert)

        XCTAssertEqual(h.lowRatedSpend, 80,   "1- and 2-star: 50 + 30")
        XCTAssertEqual(h.highRatedSpend, 160, "4- and 5-star: 40 + 120")
        XCTAssertEqual(h.totalRatedSpend, 265)
        XCTAssertEqual(h.ratedCount, 5)
    }

    func test_perCategory_averagesAndOrderedWorstFirst() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let dining = cat(ctx, "Dining")
        let groceries = cat(ctx, "Groceries")

        _ = tx(ctx, amount: -50, payee: "Domino's",  rating: 1, category: dining)
        _ = tx(ctx, amount: -30, payee: "Bunsen",    rating: 3, category: dining)
        _ = tx(ctx, amount: -25, payee: "Tesco",     rating: 5, category: groceries)
        _ = tx(ctx, amount: -25, payee: "Lidl",      rating: 4, category: groceries)

        let h = AnalyticsMetrics.hindsightBreakdown(
            in: try ctx.fetch(FetchDescriptor<Transaction>()),
            base: "EUR", convert: identityConvert)

        XCTAssertEqual(h.perCategory.first?.name, "Dining",
                       "Worst-rated category should be first")
        XCTAssertEqual(h.perCategory.first?.averageRating ?? 0, 2.0, accuracy: 0.001)
        XCTAssertEqual(h.perCategory.last?.name, "Groceries")
        XCTAssertEqual(h.perCategory.last?.averageRating ?? 0, 4.5, accuracy: 0.001)
    }

    func test_perMerchant_filtersSingleVisitMerchants() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        // 2 visits each — qualifies for the per-merchant ranking.
        _ = tx(ctx, amount: -10, payee: "Coffee Spot", rating: 5)
        _ = tx(ctx, amount: -10, payee: "Coffee Spot", rating: 5)
        // Single visit — excluded.
        _ = tx(ctx, amount: -100, payee: "One-Off Bistro", rating: 1)

        let h = AnalyticsMetrics.hindsightBreakdown(
            in: try ctx.fetch(FetchDescriptor<Transaction>()),
            base: "EUR", convert: identityConvert)

        XCTAssertEqual(h.perMerchant.count, 1)
        XCTAssertEqual(h.perMerchant.first?.name, "Coffee Spot")
    }
}
