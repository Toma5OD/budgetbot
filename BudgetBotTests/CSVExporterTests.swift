import XCTest
import SwiftData
@testable import BudgetBot

@MainActor
final class CSVExporterTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        try PersistenceController.makeInMemory()
    }

    private func makeTx(_ ctx: ModelContext,
                        amount: Decimal, payee: String,
                        note: String? = nil) -> Transaction {
        let tx = Transaction(
            amount: amount, currency: "EUR",
            payee: payee, note: note,
            confirmed: true
        )
        ctx.insert(tx)
        return tx
    }

    func test_csv_hasHeaderAndOneRowPerTransaction() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        _ = makeTx(ctx, amount: -10, payee: "Tesco")
        _ = makeTx(ctx, amount: -4,  payee: "Coffee")

        let csv = CSVExporter.transactionsCSV(
            try ctx.fetch(FetchDescriptor<Transaction>())
        )
        let text = String(decoding: csv, as: UTF8.self)
        let lines = text.split(separator: "\n")
        XCTAssertEqual(lines.count, 3, "Header + 2 rows")
        XCTAssertTrue(lines[0].contains("Date,Payee,Category"))
    }

    func test_csv_escapesCommasAndQuotesAndNewlines() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        _ = makeTx(ctx, amount: -1, payee: "Hello, World",
                   note: "She said \"hi\"\nthen left")

        let csv = CSVExporter.transactionsCSV(
            try ctx.fetch(FetchDescriptor<Transaction>())
        )
        let text = String(decoding: csv, as: UTF8.self)
        // The payee field with a comma must be quoted.
        XCTAssertTrue(text.contains("\"Hello, World\""),
                      "Comma-containing fields must be quoted")
        // Inner quotes must be doubled inside a quoted field.
        XCTAssertTrue(text.contains("\"\"hi\"\""),
                      "Double-quoting (\\\"\\\") survives inner quotes")
    }

    func test_csv_sortsNewestFirst() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let cal = Calendar.current
        let old = Transaction(
            date: cal.date(byAdding: .day, value: -30, to: .now)!,
            amount: -1, currency: "EUR", payee: "Old", confirmed: true)
        let recent = Transaction(
            date: .now, amount: -1, currency: "EUR",
            payee: "Recent", confirmed: true)
        ctx.insert(old); ctx.insert(recent)

        let csv = CSVExporter.transactionsCSV(
            try ctx.fetch(FetchDescriptor<Transaction>())
        )
        let text = String(decoding: csv, as: UTF8.self)
        let recentIndex = text.range(of: ",Recent,")?.lowerBound
        let oldIndex = text.range(of: ",Old,")?.lowerBound
        XCTAssertNotNil(recentIndex)
        XCTAssertNotNil(oldIndex)
        XCTAssertLessThan(recentIndex!, oldIndex!,
                          "Newest transaction must appear before older one")
    }

    func test_suggestedFilename_isDateStamped() {
        let f = CSVExporter.suggestedFilename(
            date: ISO8601DateFormatter().date(from: "2026-05-15T00:00:00Z")!
        )
        XCTAssertEqual(f, "budgetbot-transactions-2026-05-15.csv")
    }
}
