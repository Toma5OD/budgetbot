import XCTest
@testable import BudgetBot

final class TransactionQueryTests: XCTestCase {

    private let iso: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func snap(_ day: String, _ payee: String, _ amount: Decimal,
                     category: String = "Other", account: String = "Main",
                     currency: String = "USD") -> TransactionQuery.Snapshot {
        .init(
            date: iso.date(from: day)!,
            payee: payee, category: category, account: account,
            amount: amount, currency: currency,
            amountInBase: amount, baseCurrency: "USD"
        )
    }

    private lazy var fixture: [TransactionQuery.Snapshot] = [
        snap("2026-05-01", "Starbucks",       -4.50, category: "Coffee"),
        snap("2026-05-02", "Trader Joe's",   -32.10, category: "Groceries"),
        snap("2026-05-04", "Starbucks",       -6.25, category: "Coffee"),
        snap("2026-05-05", "Salary",        2500.00, category: "Salary"),
        snap("2026-05-10", "Costa",           -3.20, category: "Coffee"),
        snap("2026-04-30", "Tesco",          -52.40, category: "Groceries")
    ]

    func test_filterByPayeeContains_isCaseInsensitive() {
        let rows = TransactionQuery().execute(
            args: .init(payee_contains: "starbucks"),
            against: fixture
        )
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.allSatisfy { $0.payee.lowercased().contains("starbucks") })
    }

    func test_filterByCategory_isCaseInsensitive() {
        let rows = TransactionQuery().execute(
            args: .init(category: "coffee"),
            against: fixture
        )
        XCTAssertEqual(rows.count, 3)
    }

    func test_filterByDateRange_inclusive() {
        let rows = TransactionQuery().execute(
            args: .init(start_date: "2026-05-01", end_date: "2026-05-04"),
            against: fixture
        )
        // 3 entries on May 1, 2, 4
        XCTAssertEqual(rows.count, 3)
    }

    func test_filterByAmountRange_usesAbsolute() {
        let rows = TransactionQuery().execute(
            args: .init(min_amount: 30, max_amount: 60),
            against: fixture
        )
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(Set(rows.map { $0.payee }), ["Trader Joe's", "Tesco"])
    }

    func test_filterBySign_positiveOnlyKeepsIncome() {
        let rows = TransactionQuery().execute(
            args: .init(sign: "positive"),
            against: fixture
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.payee, "Salary")
    }

    func test_filterBySign_negativeOnlyKeepsExpenses() {
        let rows = TransactionQuery().execute(
            args: .init(sign: "negative"),
            against: fixture
        )
        XCTAssertEqual(rows.count, 5)
        XCTAssertFalse(rows.contains { $0.payee == "Salary" })
    }

    func test_resultsSortedNewestFirst() {
        let rows = TransactionQuery().execute(args: .init(), against: fixture)
        let dates = rows.map { $0.date }
        XCTAssertEqual(dates, dates.sorted(by: >))
    }

    func test_limitCaps() {
        let rows = TransactionQuery().execute(args: .init(limit: 2), against: fixture)
        XCTAssertEqual(rows.count, 2)
    }

    func test_limitClampedAtMax200() {
        let rows = TransactionQuery().execute(args: .init(limit: 10_000), against: fixture)
        XCTAssertEqual(rows.count, fixture.count)
    }

    func test_compoundFilters() {
        let rows = TransactionQuery().execute(
            args: .init(
                start_date: "2026-05-01",
                payee_contains: "starbucks",
                min_amount: 5,
                sign: "negative"
            ),
            against: fixture
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.payee, "Starbucks")
        XCTAssertEqual(rows.first?.date, "2026-05-04")
    }
}
