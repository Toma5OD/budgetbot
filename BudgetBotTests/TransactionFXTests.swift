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
        let tx = Transaction(
            amount: 100, currency: "USD",
            fxRateToBase: Decimal(string: "0.90")!,
            fxBaseCurrency: "EUR"
        )
        XCTAssertEqual(tx.amountInBase("EUR", liveConvert: liveConvert), 90)
    }

    func test_amountInBase_ignoresSnapshotWhenBaseChanged() {
        let tx = Transaction(
            amount: 100, currency: "USD",
            fxRateToBase: Decimal(string: "0.90")!,
            fxBaseCurrency: "EUR"
        )
        let result = tx.amountInBase("GBP", liveConvert: liveConvert)
        XCTAssertNotEqual(result, 90)
        XCTAssertGreaterThan(result, 70)
        XCTAssertLessThan(result, 80)
    }

    func test_amountInBase_fallsBackToLiveWhenNoSnapshot() {
        let tx = Transaction(amount: 110, currency: "USD")
        XCTAssertEqual(tx.amountInBase("EUR", liveConvert: liveConvert), 100)
    }

    func test_snapshotFX_sameCurrencyReturnsOne() {
        let snap = CaptureViewModel.snapshotFX(from: "USD", to: "USD", rates: liveRates)
        XCTAssertEqual(snap.rate, 1)
        XCTAssertEqual(snap.base, "USD")
    }

    func test_snapshotFX_writesCanonicalRate() {
        let snap = CaptureViewModel.snapshotFX(from: "USD", to: "EUR", rates: liveRates)
        XCTAssertEqual(snap.base, "EUR")
        guard let r = snap.rate else { return XCTFail("expected a rate") }
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

    // MARK: - Splits-aware aggregation

    func test_categorisedSlices_nonSplit_returnsSingleEntry() {
        let cat = TxCategory(name: "Groceries", kind: .expense)
        let tx = Transaction(amount: -50, currency: "EUR", payee: "Lidl", category: cat)
        let slices = tx.categorisedSlices(in: "EUR", liveConvert: liveConvert)
        XCTAssertEqual(slices.count, 1)
        XCTAssertEqual(slices.first?.amount, -50)
        XCTAssertEqual(slices.first?.category?.name, "Groceries")
    }

    func test_categorisedSlices_splitTransaction_returnsOnePerSplit() {
        let food = TxCategory(name: "Groceries", kind: .expense)
        let med  = TxCategory(name: "Health",    kind: .expense)
        let tx = Transaction(amount: -32, currency: "EUR", payee: "Tesco")
        tx.splits = [
            Split(description: "Food",     amount: -25,  category: food, transaction: tx),
            Split(description: "Medicine", amount: -7,   category: med,  transaction: tx)
        ]
        let slices = tx.categorisedSlices(in: "EUR", liveConvert: liveConvert)
        XCTAssertEqual(slices.count, 2)
        XCTAssertEqual(Set(slices.compactMap { $0.category?.name }), ["Groceries", "Health"])
        XCTAssertEqual(slices.map { $0.amount }.reduce(Decimal(0), +), -32)
    }

    func test_categorisedSlices_appliesFXSnapshot() {
        let tx = Transaction(
            amount: -100, currency: "USD", payee: "X",
            fxRateToBase: Decimal(string: "0.9")!, fxBaseCurrency: "EUR"
        )
        tx.splits = [Split(description: "A", amount: -100, transaction: tx)]
        let slices = tx.categorisedSlices(in: "EUR", liveConvert: liveConvert)
        XCTAssertEqual(slices.first?.amount, -90)
    }
}
