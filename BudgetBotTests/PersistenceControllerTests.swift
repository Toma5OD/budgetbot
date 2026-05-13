import XCTest
import SwiftData
@testable import BudgetBot

@MainActor
final class PersistenceControllerTests: XCTestCase {

    func test_inMemoryContainerWritesAndReadsBack() throws {
        let container = try PersistenceController.makeInMemory()
        let ctx = container.mainContext

        let profile = UserProfile(appleUserID: "abc", displayName: "Tom", email: "t@x.com")
        ctx.insert(profile)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<UserProfile>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.appleUserID, "abc")
        XCTAssertEqual(fetched.first?.aiModel, AIService.defaultModel)
    }

    func test_transactionCascadeDeletesSplits() throws {
        let container = try PersistenceController.makeInMemory()
        let ctx = container.mainContext

        let acc = Account(name: "X", kind: .bank)
        ctx.insert(acc)

        let tx = Transaction(amount: -30, payee: "Tesco", account: acc)
        ctx.insert(tx)
        ctx.insert(Split(description: "A", amount: -10, transaction: tx))
        ctx.insert(Split(description: "B", amount: -20, transaction: tx))
        try ctx.save()

        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Split>()).count, 2)
        ctx.delete(tx)
        try ctx.save()
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Split>()).count, 0,
                       "Cascade delete from Transaction should remove its Splits")
    }

    func test_accountCascadeDeletesTransactionsAndSplits() throws {
        let container = try PersistenceController.makeInMemory()
        let ctx = container.mainContext

        let acc = Account(name: "Tmp", kind: .bank)
        ctx.insert(acc)
        let tx = Transaction(amount: -10, payee: "x", account: acc)
        ctx.insert(tx)
        ctx.insert(Split(description: "a", amount: -10, transaction: tx))
        try ctx.save()

        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Transaction>()).count, 1)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Split>()).count, 1)
        ctx.delete(acc)
        try ctx.save()
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Transaction>()).count, 0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Split>()).count, 0)
    }

    func test_seedCategoriesAreUniqueByName() throws {
        let container = try PersistenceController.makeInMemory()
        let ctx = container.mainContext
        for (name, kind, emoji) in TxCategory.defaults {
            ctx.insert(TxCategory(name: name, kind: kind, emoji: emoji))
        }
        try ctx.save()
        let cats = try ctx.fetch(FetchDescriptor<TxCategory>())
        XCTAssertEqual(cats.count, TxCategory.defaults.count)
        XCTAssertEqual(Set(cats.map { $0.name }).count, cats.count)
    }
}
