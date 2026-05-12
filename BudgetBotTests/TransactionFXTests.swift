import XCTest
@testable import BudgetBot

@MainActor
final class TransactionFXTests: XCTestCase {

    private let liveRates: [String: Decimal] = [
        "EUR": 1.0, "USD": Decimal(string: "1.10")!, "GBP": Decimal(string: "0.85")!
    ]

    private func liveConvert(_ amt: Decimal, _ from: String, _ to: String) -> Decimal {
        FXService.convert(amt, from: from, to: to, rates: liveRates)
    }

    func test_amountInBase_usesSnapshotWhenBaseMatches() {
        // Snapshot says 1 USD = 0.90 EUR.
        let tx = Transaction(
            amount: 100, currency: "USD",
            fxRateToBase: Decimal(string: "0.90")!,
            fxBaseCurrency: "EUR"
        )
        // Live rates would say 100 USD ≈ 90.9 EUR (100 / 1.10 * 1.0).
        // We expect the snapshot: 100 * 0.90 = 90.
        let result = tx.amountInBase("EUR", liveConvert: liveConvert)
        XCTAssertEqual(result, 90)
    }

    func test_amountInBase_ignoresSnapshotWhenBaseChanged() {
        let tx = Transaction(
            amount: 100, currency: "USD",
            fxRateToBase: Decimal(string: "0.90")!,
            fxBaseCurrency: "EUR"
        )
        // User now bases in GBP. The EUR-relative snapshot doesn't apply.
        // Live: 100 USD -> 90.909... EUR -> 77.27... GBP
        let result = tx.amountInBase("GBP", liveConvert: liveConvert)
        // Should be the live-converted value, not 100 × 0.90.
        XCTAssertNotEqual(result, 90)
        XCTAssertGreaterThan(result, 70)
        XCTAssertLessThan(result, 80)
    }

    func test_amountInBase_fallsBackToLiveWhenNoSnapshot() {
        let tx = Transaction(amount: 110, currency: "USD")
        // 110 USD -> 100 EUR (rate 1.10)
        let result = tx.amountInBase("EUR", liveConvert: liveConvert)
        XCTAssertEqual(result, 100)
    }

    func test_snapshotFX_sameCurrencyReturnsOne() {
        let snap = CaptureViewModel.snapshotFX(from: "USD", to: "USD", rates: liveRates)
        XCTAssertEqual(snap.rate, 1)
        XCTAssertEqual(snap.base, "USD")
    }

    func test_snapshotFX_writesCanonicalRate() {
        // 1 USD -> 0.909... EUR  (1 / 1.10)
        let snap = CaptureViewModel.snapshotFX(from: "USD", to: "EUR", rates: liveRates)
        XCTAssertEqual(snap.base, "EUR")
        guard let r = snap.rate else { return XCTFail("expected a rate") }
        // Within a tiny tolerance.
        let target = Decimal(1) / Decimal(string: "1.10")!
        XCTAssertEqual(NSDecimalNumber(decimal: r).doubleValue,
                       NSDecimalNumber(decimal: target).doubleValue,
                       accuracy: 0.0001)
    }

    func test_snapshotFX_missingRateReturnsNil() {
        let snap = CaptureViewModel.snapshotFX(from: "ZZZ", to: "USD", rates: liveRates)
        XCTAssertNil(snap.rate)
        XCTAssertNil(snap.base)
    }

    func test_amountInBase_baseCaseInsensitiveMatch() {
        // Snapshot was taken with "eur" (shouldn't happen in code, defensive).
        let tx = Transaction(
            amount: 100, currency: "USD",
            fxRateToBase: Decimal(string: "0.90")!,
            fxBaseCurrency: "eur"
        )
        let result = tx.amountInBase("EUR", liveConvert: liveConvert)
        XCTAssertEqual(result, 90)
    }
}
