import XCTest
import SwiftData
@testable import BudgetBot

@MainActor
final class HindsightRatingTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        try PersistenceController.makeInMemory()
    }

    func test_freshTransaction_hasNilRating() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let tx = Transaction(amount: -10, currency: "EUR", payee: "X")
        ctx.insert(tx)
        XCTAssertNil(tx.hindsightRating)
        XCTAssertNil(tx.hindsightRatedAt)
    }

    func test_settingRating_persists() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let tx = Transaction(amount: -10, currency: "EUR", payee: "X",
                             confirmed: true)
        ctx.insert(tx)

        tx.hindsightRating = 4
        tx.hindsightRatedAt = .now
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(fetched.first?.hindsightRating, 4)
        XCTAssertNotNil(fetched.first?.hindsightRatedAt)
    }

    func test_unratedExpenses_queryFiltersIncomeAndRated() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let unrated = Transaction(amount: -10, currency: "EUR", payee: "Unrated",
                                  confirmed: true)
        let rated = Transaction(amount: -10, currency: "EUR", payee: "Rated",
                                confirmed: true, hindsightRating: 3)
        let income = Transaction(amount: 1000, currency: "EUR", payee: "Salary",
                                 confirmed: true)
        let unconfirmed = Transaction(amount: -5, currency: "EUR", payee: "Pending",
                                      confirmed: false)
        ctx.insert(unrated); ctx.insert(rated); ctx.insert(income); ctx.insert(unconfirmed)
        try ctx.save()

        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate {
                $0.confirmed && $0.hindsightRating == nil && $0.amount < 0
            }
        )
        let results = try ctx.fetch(descriptor)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.payee, "Unrated",
                       "Only confirmed expense transactions without a rating should be returned")
    }

    func test_clearingRating_resetsBoth() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let tx = Transaction(amount: -10, currency: "EUR", payee: "X",
                             confirmed: true, hindsightRating: 2,
                             hindsightRatedAt: .now)
        ctx.insert(tx)
        try ctx.save()

        tx.hindsightRating = nil
        tx.hindsightRatedAt = nil
        try ctx.save()

        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate {
                $0.confirmed && $0.hindsightRating == nil && $0.amount < 0
            }
        )
        XCTAssertEqual(try ctx.fetch(descriptor).count, 1,
                       "After clearing, tx should reappear as unrated")
    }
}
