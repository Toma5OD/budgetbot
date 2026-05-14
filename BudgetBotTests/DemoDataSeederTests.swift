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
        XCTAssertEqual(accounts.count, 3, "Three demo accounts: bank, cash, credit")

        let categories = try ctx.fetch(FetchDescriptor<TxCategory>())
        XCTAssertEqual(categories.count, TxCategory.defaults.count,
                       "All default categories are seeded")

        let txs = try ctx.fetch(FetchDescriptor<Transaction>())
        XCTAssertGreaterThan(txs.count, 40,
                             "Seeder should populate enough history to make analytics meaningful")
        XCTAssertTrue(txs.allSatisfy(\.confirmed),
                      "Demo transactions are pre-confirmed so they show up immediately")
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
        XCTAssertFalse(splits.isEmpty, "Demo data exercises the split path")
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
