import XCTest
import SwiftData
@testable import BudgetBot

@MainActor
final class BankTransactionImporterTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        try PersistenceController.makeInMemory()
    }

    private func makeAccount(_ ctx: ModelContext) -> Account {
        let a = Account(name: "Revolut", kind: .bank, currency: "EUR")
        ctx.insert(a)
        return a
    }

    private func makeRaw(id: String, payee: String,
                         amount: Decimal, daysAgo: Int = 1) -> BankTransactionRaw {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        return BankTransactionRaw(
            id: id, accountID: "acct-1", date: date, postedAt: date,
            amount: amount, currency: "EUR",
            merchant: payee, description: payee
        )
    }

    func test_firstImport_insertsAll() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let account = makeAccount(ctx)

        let result = try BankTransactionImporter.importRows([
            makeRaw(id: "tx-1", payee: "Tesco",   amount: -22.50),
            makeRaw(id: "tx-2", payee: "Spotify", amount: -11.99)
        ], into: account, context: ctx)

        XCTAssertEqual(result.inserted, 2)
        XCTAssertEqual(result.updated, 0)
        XCTAssertEqual(result.skippedDuplicate, 0)
    }

    func test_secondImport_withSameExternalIDs_updatesNotInserts() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let account = makeAccount(ctx)

        _ = try BankTransactionImporter.importRows([
            makeRaw(id: "tx-1", payee: "Tesco", amount: -22.50)
        ], into: account, context: ctx)
        // Same id, slightly different amount (bank corrected the row).
        let result2 = try BankTransactionImporter.importRows([
            makeRaw(id: "tx-1", payee: "Tesco", amount: -23.10)
        ], into: account, context: ctx)

        XCTAssertEqual(result2.inserted, 0)
        XCTAssertEqual(result2.updated, 1)
        let txs = try ctx.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(txs.count, 1, "Update path keeps the row count constant")
        XCTAssertEqual(txs.first?.amount, -23.10,
                       "Amount should be corrected to the latest pull")
    }

    func test_softDedup_skipsRowMatchingExistingManualEntry() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let account = makeAccount(ctx)
        // A manual tx the user entered themselves — no externalID.
        let date = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let manual = Transaction(
            date: date, amount: -42.00, currency: "EUR",
            payee: "Tesco", confirmed: true
        )
        ctx.insert(manual)
        try ctx.save()

        // Bank pull surfaces the same purchase with its own id and a
        // payee string that normalises to the same key as the manual
        // entry's. Trailing " 04" gets stripped by PayeeNormaliser, so
        // "Tesco 04" → key "tesco" → matches the manual "Tesco".
        let result = try BankTransactionImporter.importRows([
            BankTransactionRaw(
                id: "bank-id-1", accountID: "acct-1",
                date: date, postedAt: date,
                amount: -42.00, currency: "EUR",
                merchant: "Tesco 04",
                description: "Tesco 04"
            )
        ], into: account, context: ctx)

        XCTAssertEqual(result.skippedDuplicate, 1,
                       "Bank row matching a manual entry by payee/date/amount must be skipped")
        let txs = try ctx.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(txs.count, 1)
    }

    func test_externalIDMatch_takesPrecedenceOverFuzzy() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let account = makeAccount(ctx)

        // First pull — creates with external id.
        _ = try BankTransactionImporter.importRows([
            makeRaw(id: "bank-id-1", payee: "Tesco", amount: -10)
        ], into: account, context: ctx)

        // Second pull — same id, same payee, same date — should be
        // recognised as the same transaction and update, not soft-dup.
        let result = try BankTransactionImporter.importRows([
            makeRaw(id: "bank-id-1", payee: "Tesco", amount: -10.50)
        ], into: account, context: ctx)
        XCTAssertEqual(result.updated, 1)
        XCTAssertEqual(result.skippedDuplicate, 0)
    }
}
