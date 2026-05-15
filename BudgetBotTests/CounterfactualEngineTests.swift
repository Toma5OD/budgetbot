import XCTest
import SwiftData
@testable import BudgetBot

@MainActor
final class CounterfactualEngineTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        try PersistenceController.makeInMemory()
    }

    private let identityConvert: CounterfactualEngine.Converter = { amt, _, _ in amt }

    private func tx(_ ctx: ModelContext,
                    amount: Decimal,
                    payee: String,
                    daysAgo: Int,
                    categoryName: String? = nil,
                    isRegret: Bool = false) -> Transaction {
        let cal = Calendar(identifier: .gregorian)
        let date = cal.date(byAdding: .day, value: -daysAgo, to: .now)!
        let cat: TxCategory? = categoryName.map {
            let c = TxCategory(name: $0, kind: .expense); ctx.insert(c); return c
        }
        let t = Transaction(
            date: date, amount: amount, currency: "EUR",
            payee: payee, confirmed: true,
            isRegret: isRegret,
            category: cat
        )
        ctx.insert(t)
        return t
    }

    // MARK: - Vice pools

    func test_alcoholPool_sumsCategoryAndMerchantMatches() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // Category match.
        _ = tx(ctx, amount: -30, payee: "Some Pub", daysAgo: 5, categoryName: "Alcohol")
        // Merchant match (Long Hall is in MerchantClassifier's alcohol list).
        _ = tx(ctx, amount: -45, payee: "The Long Hall", daysAgo: 10)
        // Non-alcohol.
        _ = tx(ctx, amount: -20, payee: "Tesco", daysAgo: 7, categoryName: "Groceries")

        let pools = CounterfactualEngine.vicePools(
            in: try ctx.fetch(FetchDescriptor<Transaction>()),
            base: "EUR", convert: identityConvert)

        let alcohol = pools.first { $0.id == "alcohol" }
        XCTAssertNotNil(alcohol)
        XCTAssertEqual(alcohol?.annualEUR, 75,
                       "Both alcohol entries (30 + 45) summed into the annual figure")
    }

    func test_finePools_excludeOldTransactionsBeyond12Months() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // 14 months ago → outside both 3m and 12m windows.
        _ = tx(ctx, amount: -100, payee: "Old Pub", daysAgo: 14 * 30,
               categoryName: "Alcohol")
        // 2 months ago → inside both.
        _ = tx(ctx, amount: -50, payee: "Recent Pub", daysAgo: 60,
               categoryName: "Alcohol")

        let pools = CounterfactualEngine.vicePools(
            in: try ctx.fetch(FetchDescriptor<Transaction>()),
            base: "EUR", convert: identityConvert)

        XCTAssertEqual(pools.first(where: { $0.id == "alcohol" })?.annualEUR, 50,
                       "Old transaction outside 12-month window must not count")
    }

    func test_regretBucket_picksUpRegretFlaggedTxAcrossCategories() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        _ = tx(ctx, amount: -38, payee: "Domino's", daysAgo: 5,
               categoryName: "Dining", isRegret: true)

        let pools = CounterfactualEngine.vicePools(
            in: try ctx.fetch(FetchDescriptor<Transaction>()),
            base: "EUR", convert: identityConvert)

        XCTAssertEqual(pools.first(where: { $0.id == "regret" })?.annualEUR, 38,
                       "isRegret transactions land in the regret pool regardless of category")
    }

    // MARK: - Vice comparisons

    func test_viceComparisons_emptyWhenNoSpend() {
        let comparisons = CounterfactualEngine.viceComparisons(pools: [])
        XCTAssertTrue(comparisons.isEmpty)
    }

    func test_viceComparisons_pickClosestMultipliers() {
        // €5,000 of alcohol over the year — should pair with one of
        // the lifestyle-sized targets (engagement ring at €5k is a
        // 1.0× match — perfect for the "closeness to hero" sort).
        let pool = CounterfactualEngine.VicePool(
            id: "alcohol", label: "alcohol", emoji: "🍻",
            monthlyEUR: 416.67, annualEUR: 5000
        )
        let comparisons = CounterfactualEngine.viceComparisons(
            pools: [pool],
            dreams: [],
            catalogue: ReferencePurchase.all
        )
        XCTAssertFalse(comparisons.isEmpty)
        // Top comparison should be closer to 1× than to 10× or 0.1×.
        let top = comparisons.first!
        XCTAssertTrue(top.multiplier > 0.5 && top.multiplier < 2.0,
                      "Top counterfactual should sit in the 0.5–2× hero band, got \(top.multiplier)")
    }

    func test_viceComparisons_userDreamsAreIncluded() {
        let pool = CounterfactualEngine.VicePool(
            id: "alcohol", label: "alcohol", emoji: "🍻",
            monthlyEUR: 100, annualEUR: 1200
        )
        let dream = UserDream(name: "Japan trip", targetPrice: 1000,
                              currency: "EUR")
        let comparisons = CounterfactualEngine.viceComparisons(
            pools: [pool], dreams: [dream], catalogue: ReferencePurchase.all
        )
        XCTAssertTrue(comparisons.contains { $0.target.isUserDream },
                      "User dreams should appear in the comparison set")
    }

    // MARK: - Savings comparisons

    func test_savingsComparisons_emptyWhenNoSavings() {
        let result = CounterfactualEngine.savingsComparisons(monthlySavingsEUR: 0)
        XCTAssertTrue(result.isEmpty)
    }

    func test_savingsComparisons_orderedByMonthsToTarget() {
        let dream1 = UserDream(name: "Honeymoon", targetPrice: 2000)
        let dream2 = UserDream(name: "House deposit", targetPrice: 40_000)
        let result = CounterfactualEngine.savingsComparisons(
            monthlySavingsEUR: 500,
            dreams: [dream1, dream2],
            catalogue: []
        )
        XCTAssertEqual(result.first?.target.name, "Honeymoon",
                       "Nearer target should be sorted first")
        XCTAssertEqual(result.last?.target.name, "House deposit")
    }

    func test_savingsComparisons_computeMonthsCorrectly() {
        let dream = UserDream(name: "Anything", targetPrice: 1000)
        let result = CounterfactualEngine.savingsComparisons(
            monthlySavingsEUR: 250,
            dreams: [dream],
            catalogue: []
        )
        XCTAssertEqual(result.first?.monthsToTarget, 4,
                       "1000 / 250 = 4 months")
    }
}
