import XCTest
import SwiftData
@testable import BudgetBot

final class MerchantCategoryTests: XCTestCase {

    func test_resolvesCommonMerchants() {
        XCTAssertEqual(MerchantCategory.resolve("Tesco Express Camden"), "Groceries")
        XCTAssertEqual(MerchantCategory.resolve("Lidl"), "Groceries")
        XCTAssertEqual(MerchantCategory.resolve("Circle K"), "Fuel")
        XCTAssertEqual(MerchantCategory.resolve("Boots Pharmacy Henry St"), "Pharmacy")
        XCTAssertEqual(MerchantCategory.resolve("Electric Ireland"), "Electricity")
        XCTAssertEqual(MerchantCategory.resolve("Netflix"), "Streaming")
        XCTAssertEqual(MerchantCategory.resolve("Dublin Bus"), "Public Transport")
    }

    func test_unknownMerchant_returnsNil() {
        XCTAssertNil(MerchantCategory.resolve("Joe's Window Cleaning"))
        XCTAssertNil(MerchantCategory.resolve(""))
    }
}

@MainActor
final class CategoryBackfillTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try PersistenceController.makeInMemory())
    }

    func test_fillsCategoryFromMerchant() throws {
        let ctx = try makeContext()
        ctx.insert(TxCategory(name: "Groceries", kind: .expense, emoji: "🛒"))
        let tx = Transaction(amount: -50, currency: "EUR", payee: "Tesco Express")
        ctx.insert(tx)
        try ctx.save()

        XCTAssertEqual(CategoryBackfill.run(in: ctx), 1)
        XCTAssertEqual(tx.category?.name, "Groceries")
    }

    func test_doesNotOverwriteExistingCategory() throws {
        let ctx = try makeContext()
        let dining = TxCategory(name: "Dining", kind: .expense, emoji: "🍔")
        ctx.insert(dining)
        ctx.insert(TxCategory(name: "Groceries", kind: .expense, emoji: "🛒"))
        let tx = Transaction(amount: -50, currency: "EUR", payee: "Tesco", category: dining)
        ctx.insert(tx)
        try ctx.save()

        XCTAssertEqual(CategoryBackfill.run(in: ctx), 0)
        XCTAssertEqual(tx.category?.name, "Dining")
    }

    func test_skipsIncomeAndUnknownMerchants() throws {
        let ctx = try makeContext()
        ctx.insert(TxCategory(name: "Groceries", kind: .expense, emoji: "🛒"))
        let income  = Transaction(amount: 100, currency: "EUR", payee: "Tesco refund")
        let unknown = Transaction(amount: -10, currency: "EUR", payee: "Joe's Window Cleaning")
        ctx.insert(income); ctx.insert(unknown)
        try ctx.save()

        XCTAssertEqual(CategoryBackfill.run(in: ctx), 0)
        XCTAssertNil(income.category)
        XCTAssertNil(unknown.category)
    }

    func test_skipsAlreadySplitTransactions() throws {
        let ctx = try makeContext()
        ctx.insert(TxCategory(name: "Groceries", kind: .expense, emoji: "🛒"))
        let tx = Transaction(amount: -50, currency: "EUR", payee: "Tesco")
        ctx.insert(tx)
        ctx.insert(Split(description: "x", amount: -50, transaction: tx))
        try ctx.save()

        XCTAssertEqual(CategoryBackfill.run(in: ctx), 0, "itemised rows classify per split")
        XCTAssertNil(tx.category)
    }
}
