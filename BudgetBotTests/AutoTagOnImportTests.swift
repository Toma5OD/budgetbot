import XCTest
import SwiftData
@testable import BudgetBot

@MainActor
final class AutoTagOnImportTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        try PersistenceController.makeInMemory()
    }

    private func seedCategories(_ ctx: ModelContext, _ names: [String]) {
        for n in names {
            ctx.insert(TxCategory(name: n, kind: .expense))
        }
    }

    private func rawRow(merchant: String,
                        amount: Decimal = -10,
                        categoryHint: String? = nil) -> BankTransactionRaw {
        BankTransactionRaw(
            id: UUID().uuidString,
            accountID: "acct",
            date: .now, postedAt: .now,
            amount: amount, currency: "EUR",
            merchant: merchant, description: merchant,
            categoryHint: categoryHint
        )
    }

    func test_coffeeMerchant_getsCoffeeCategory() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        seedCategories(ctx, ["Coffee", "Dining", "Alcohol", "Groceries"])
        let account = Account(name: "Bank", kind: .bank, currency: "EUR")
        ctx.insert(account)

        _ = try BankTransactionImporter.importRows(
            [rawRow(merchant: "Insomnia Coffee")],
            into: account, context: ctx)

        let tx = try ctx.fetch(FetchDescriptor<Transaction>()).first!
        XCTAssertEqual(tx.category?.name, "Coffee",
                       "Coffee chain should auto-tag as Coffee even with no bank hint")
    }

    func test_fastFoodMerchant_getsDiningCategory() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        seedCategories(ctx, ["Coffee", "Dining", "Alcohol", "Groceries"])
        let account = Account(name: "Bank", kind: .bank, currency: "EUR")
        ctx.insert(account)

        _ = try BankTransactionImporter.importRows(
            [rawRow(merchant: "Domino's Pizza Camden")],
            into: account, context: ctx)

        let tx = try ctx.fetch(FetchDescriptor<Transaction>()).first!
        XCTAssertEqual(tx.category?.name, "Dining",
                       "Fast food classifier maps to the Dining category")
    }

    func test_alcoholMerchant_getsAlcoholCategory() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        seedCategories(ctx, ["Coffee", "Dining", "Alcohol", "Groceries"])
        let account = Account(name: "Bank", kind: .bank, currency: "EUR")
        ctx.insert(account)

        _ = try BankTransactionImporter.importRows(
            [rawRow(merchant: "Eight Degrees Brewing — Taproom")],
            into: account, context: ctx)

        let tx = try ctx.fetch(FetchDescriptor<Transaction>()).first!
        XCTAssertEqual(tx.category?.name, "Alcohol")
    }

    func test_bankCategoryHintWinsOverClassifier() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        seedCategories(ctx, ["Coffee", "Groceries"])
        let account = Account(name: "Bank", kind: .bank, currency: "EUR")
        ctx.insert(account)

        // Coffee shop merchant but bank says it's groceries — bank wins.
        _ = try BankTransactionImporter.importRows(
            [rawRow(merchant: "Insomnia Coffee", categoryHint: "Groceries")],
            into: account, context: ctx)

        let tx = try ctx.fetch(FetchDescriptor<Transaction>()).first!
        XCTAssertEqual(tx.category?.name, "Groceries",
                       "Bank's explicit hint should win over the merchant heuristic")
    }

    func test_unrecognisedMerchant_staysUncategorised() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        seedCategories(ctx, ["Coffee", "Dining"])
        let account = Account(name: "Bank", kind: .bank, currency: "EUR")
        ctx.insert(account)

        _ = try BankTransactionImporter.importRows(
            [rawRow(merchant: "Random Hardware Co")],
            into: account, context: ctx)

        let tx = try ctx.fetch(FetchDescriptor<Transaction>()).first!
        XCTAssertNil(tx.category,
                     "Unknown merchant + no bank hint → uncategorised (user assigns)")
    }
}
