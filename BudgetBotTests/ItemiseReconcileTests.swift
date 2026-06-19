import XCTest
@testable import BudgetBot

final class ItemiseReconcileTests: XCTestCase {

    private func line(_ amount: Decimal, qty: Int = 1) -> ItemisedLine {
        ItemisedLine(description: "x", quantity: qty, amount: amount, category: nil)
    }

    private func sum(_ lines: [ItemisedLine]) -> Decimal {
        lines.reduce(Decimal(0)) { $0 + $1.amount }
    }

    func test_alreadyExact_isPreserved() {
        let out = AIService.reconcile([line(2), line(2)], to: 4)
        XCTAssertEqual(sum(out), 4)
        XCTAssertEqual(out.map(\.amount), [2, 2])
    }

    func test_scalesDownToTotal() {
        // AI returned items twice the real total — scale to fit.
        let out = AIService.reconcile([line(6), line(2)], to: 4)
        XCTAssertEqual(sum(out), 4)
        XCTAssertEqual(out.map(\.amount), [3, 1])
    }

    func test_roundingResidualLandsAndSumsExactly() {
        // 10 / 3 doesn't divide evenly; the penny must still reconcile.
        let out = AIService.reconcile([line(1), line(1), line(1)], to: 10)
        XCTAssertEqual(sum(out), 10, "must sum to the exact total")
        // No line negative, none absurd.
        XCTAssertTrue(out.allSatisfy { $0.amount > 0 })
    }

    func test_offByAPennyIsForcedToTotal() {
        let out = AIService.reconcile([line(1.99), line(2.00)], to: 4)
        XCTAssertEqual(sum(out), 4)
    }

    func test_zeroAmounts_splitEvenly() {
        let out = AIService.reconcile([line(0), line(0)], to: 5)
        XCTAssertEqual(sum(out), 5)
    }

    func test_emptyAndNonPositiveTotal_returnedAsIs() {
        XCTAssertTrue(AIService.reconcile([], to: 4).isEmpty)
        let zero = AIService.reconcile([line(2), line(2)], to: 0)
        XCTAssertEqual(zero.map(\.amount), [2, 2])   // untouched
    }

    func test_preservesDescriptionsAndQuantities() {
        let input = [
            ItemisedLine(description: "Lighter", quantity: 2, amount: 4, category: "Shopping")
        ]
        let out = AIService.reconcile(input, to: 4)
        XCTAssertEqual(out.first?.description, "Lighter")
        XCTAssertEqual(out.first?.quantity, 2)
        XCTAssertEqual(out.first?.category, "Shopping")
        XCTAssertEqual(out.first?.unitAmount, 2)
    }
}
