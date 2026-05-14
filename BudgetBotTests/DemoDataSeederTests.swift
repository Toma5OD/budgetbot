import XCTest
import SwiftData
@testable import BudgetBot

@MainActor
final class DemoDataSeederTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        try PersistenceController.makeInMemory()
    }

    func test_seedingProducesAFullPersona() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        try DemoDataSeeder.wipeAndSeed(in: ctx)

        let profiles = try ctx.fetch(FetchDescriptor<UserProfile>())
        XCTAssertEqual(profiles.count, 1, "Exactly one demo profile is inserted")
        XCTAssertEqual(profiles.first?.displayName, "Sam Sample")

        let accounts = try ctx.fetch(FetchDescriptor<Account>())
        XCTAssertEqual(accounts.count, 4,
                       "Four demo accounts: two banks (Revolut + AIB), cash, credit")
        let kinds = Set(accounts.map(\.kind))
        XCTAssertTrue(kinds.contains(.bank),   "Seeder includes at least one bank account")
        XCTAssertTrue(kinds.contains(.cash),   "Seeder includes a cash account")
        XCTAssertTrue(kinds.contains(.credit), "Seeder includes a credit account for FX testing")

        let categories = try ctx.fetch(FetchDescriptor<TxCategory>())
        XCTAssertEqual(categories.count, TxCategory.defaults.count,
                       "All default categories are seeded")

        let txs = try ctx.fetch(FetchDescriptor<Transaction>())
        XCTAssertGreaterThan(txs.count, 100,
                             "Seeder should populate enough history (5+ months) to make analytics meaningful")
        XCTAssertTrue(txs.allSatisfy(\.confirmed),
                      "Demo transactions are pre-confirmed so they show up immediately")

        let currencies = Set(txs.map(\.currency))
        XCTAssertTrue(currencies.contains("EUR"))
        XCTAssertTrue(currencies.contains("USD"),
                      "Demo includes USD travel transactions for FX-aware screens")

        XCTAssertTrue(txs.contains { $0.amount > 0 },
                      "Demo includes income (salary, refunds) not just expenses")
        XCTAssertTrue(txs.contains { $0.fxRateToBase != nil },
                      "At least one transaction has an FX rate snapshot")
    }

    func test_seedingIncludesRegretsForHallOfShame() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        try DemoDataSeeder.wipeAndSeed(in: ctx)

        let regrets = try ctx.fetch(
            FetchDescriptor<Transaction>(predicate: #Predicate { $0.isRegret })
        )
        XCTAssertGreaterThanOrEqual(regrets.count, 4,
                                    "At least four regret entries so the Hall of Shame has content")
        XCTAssertTrue(regrets.allSatisfy { $0.regretEmoji != nil },
                      "Every demo regret has an emoji tag")
        XCTAssertTrue(regrets.allSatisfy { $0.regretNote?.isEmpty == false },
                      "Every demo regret has a roast note")
    }

    func test_seedingIncludesAtLeastOneSplitTransaction() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        try DemoDataSeeder.wipeAndSeed(in: ctx)

        let splits = try ctx.fetch(FetchDescriptor<Split>())
        XCTAssertGreaterThanOrEqual(splits.count, 2,
                                    "Demo data exercises the split path more than once")
    }

    func test_seedingIsRepeatable_wipesOldDataFirst() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        try DemoDataSeeder.wipeAndSeed(in: ctx)
        let firstTxCount = try ctx.fetch(FetchDescriptor<Transaction>()).count

        try DemoDataSeeder.wipeAndSeed(in: ctx)
        let secondTxCount = try ctx.fetch(FetchDescriptor<Transaction>()).count

        XCTAssertEqual(firstTxCount, secondTxCount,
                       "Second seed must wipe first run rather than appending")
    }
}
