import XCTest
@testable import BudgetBot

final class FXServiceTests: XCTestCase {

    private let rates: [String: Decimal] = [
        "EUR": Decimal(1.0),
        "USD": Decimal(string: "1.08")!,
        "GBP": Decimal(string: "0.86")!
    ]

    func test_convert_sameCurrencyReturnsInput() {
        let out = FXService.convert(Decimal(100), from: "USD", to: "USD", rates: rates)
        XCTAssertEqual(out, 100)
    }

    func test_convert_USD_to_EUR() {
        let out = FXService.convert(Decimal(108), from: "USD", to: "EUR", rates: rates)
        XCTAssertEqual(out, 100)
    }

    func test_convert_EUR_to_USD() {
        let out = FXService.convert(Decimal(100), from: "EUR", to: "USD", rates: rates)
        XCTAssertEqual(out, Decimal(string: "108")!)
    }

    func test_convert_USD_to_GBP_crossesViaEUR() {
        // 108 USD -> 100 EUR -> 86 GBP
        let out = FXService.convert(Decimal(108), from: "USD", to: "GBP", rates: rates)
        XCTAssertEqual(out, 86)
    }

    func test_convert_unknownCurrencyReturnsInputUntouched() {
        let out = FXService.convert(Decimal(100), from: "XYZ", to: "USD", rates: rates)
        XCTAssertEqual(out, 100)
    }

    func test_convert_caseInsensitive() {
        let out = FXService.convert(Decimal(100), from: "eur", to: "usd", rates: rates)
        XCTAssertEqual(out, Decimal(string: "108")!)
    }

    func test_convert_zeroRateBailsSafely() {
        let broken: [String: Decimal] = ["EUR": 0, "USD": 1]
        let out = FXService.convert(Decimal(100), from: "EUR", to: "USD", rates: broken)
        XCTAssertEqual(out, 100, "Should not divide by zero — return input")
    }

    // MARK: - ECB XML parsing

    func test_ECBParser_parsesRealisticSnippet() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gesmes:Envelope xmlns:gesmes="http://www.gesmes.org/xml/2002-08-01"
                         xmlns="http://www.ecb.int/vocabulary/2002-08-01/eurofxref">
            <gesmes:subject>Reference rates</gesmes:subject>
            <gesmes:Sender><gesmes:name>ECB</gesmes:name></gesmes:Sender>
            <Cube>
                <Cube time="2026-05-12">
                    <Cube currency="USD" rate="1.0800"/>
                    <Cube currency="GBP" rate="0.8600"/>
                    <Cube currency="JPY" rate="170.50"/>
                </Cube>
            </Cube>
        </gesmes:Envelope>
        """
        let parsed = try ECBRateParser().parse(Data(xml.utf8))
        XCTAssertEqual(parsed["USD"], Decimal(string: "1.0800"))
        XCTAssertEqual(parsed["GBP"], Decimal(string: "0.8600"))
        XCTAssertEqual(parsed["JPY"], Decimal(string: "170.50"))
        XCTAssertEqual(parsed.count, 3)
    }

    func test_ECBParser_throwsOnEmptyDocument() {
        let xml = "<root></root>"
        XCTAssertThrowsError(try ECBRateParser().parse(Data(xml.utf8)))
    }
}
