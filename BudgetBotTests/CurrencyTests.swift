import XCTest
@testable import BudgetBot

final class CurrencyTests: XCTestCase {

    func test_supported_includesCoreEuropeanAndUSCurrencies() {
        let codes = Set(Currencies.supported.map { $0.code })
        for expected in ["EUR", "USD", "GBP", "CHF", "JPY", "AUD", "CAD"] {
            XCTAssertTrue(codes.contains(expected), "Missing \(expected)")
        }
    }

    func test_supported_listsEuroFirst() {
        XCTAssertEqual(Currencies.supported.first?.code, "EUR",
                       "EUR should be the top of the picker for European users")
    }

    func test_supported_hasNoDuplicates() {
        let codes = Currencies.supported.map { $0.code }
        XCTAssertEqual(Set(codes).count, codes.count)
    }

    func test_by_caseInsensitive() {
        XCTAssertEqual(Currencies.by(code: "eur")?.code, "EUR")
        XCTAssertEqual(Currencies.by(code: "Usd")?.code, "USD")
    }

    func test_by_returnsNilForUnknown() {
        XCTAssertNil(Currencies.by(code: "ZZZ"))
    }

    func test_displayLabel_containsAllParts() {
        let eur = Currencies.by(code: "EUR")!
        XCTAssertTrue(eur.displayLabel.contains("EUR"))
        XCTAssertTrue(eur.displayLabel.contains("€"))
        XCTAssertTrue(eur.displayLabel.contains("Euro"))
    }

    func test_localeDefault_returnsSupportedCurrencyOrFallsBackToEUR() {
        let code = Currencies.localeDefault
        XCTAssertTrue(Currencies.supported.map(\.code).contains(code),
                      "localeDefault must always be in the supported list")
    }
}
