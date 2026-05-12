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

    func test_transactionCascadeWithAccountDelete() throws {
        let container = try PersistenceController.makeInMemory()
        let ctx = container.mainContext

        let a = Account(name: "Tmp", kind: .bank)
        ctx.insert(a)
        ctx.insert(Transaction(amount: -1, payee: "x", confirmed: true, account: a))
        ctx.insert(Transaction(amount: -2, payee: "y", confirmed: true, account: a))
        try ctx.save()

        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Transaction>()).count, 2)
        ctx.delete(a)
        try ctx.save()
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Transaction>()).count, 0,
                       "Account.transactions has cascade delete; should remove children")
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
