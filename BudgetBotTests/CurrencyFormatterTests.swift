import XCTest
@testable import BudgetBot

final class CurrencyFormatterTests: XCTestCase {

    func test_formatsUSDWithSymbol() {
        let s = CurrencyFormatter.string(for: Decimal(string: "12.34")!, currency: "USD")
        XCTAssertTrue(s.contains("12.34"))
        XCTAssertTrue(s.contains("$") || s.contains("USD"))
    }

    func test_negativeAmountsRender() {
        let s = CurrencyFormatter.string(for: Decimal(string: "-100")!, currency: "USD")
        XCTAssertTrue(s.contains("100"))
        // NumberFormatter renders "-" or parens depending on locale; just sanity-check.
        XCTAssertFalse(s.isEmpty)
    }

    func test_unknownCurrencyDoesNotCrash() {
        let s = CurrencyFormatter.string(for: Decimal(string: "1")!, currency: "ZZZZ")
        XCTAssertFalse(s.isEmpty)
    }
}
