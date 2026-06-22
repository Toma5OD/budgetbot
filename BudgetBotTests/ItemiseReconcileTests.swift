import XCTest
@testable import BudgetBot

final class ItemiseReconcileTests: XCTestCase {

    private func line(_ amount: Decimal, qty: Int = 1, desc: String = "x") -> ItemisedLine {
        ItemisedLine(description: desc, quantity: qty, amount: amount, category: nil)
    }

    // MARK: - settle: honest reconciliation

    func test_balanced_whenItemsMatchTotal() {
        let r = AIService.settle([line(2), line(2)], to: 4)
        XCTAssertEqual(r.status, .balanced)
        XCTAssertEqual(r.sum, 4)
        XCTAssertEqual(r.lines.count, 2)
    }

    func test_roundingNoise_snapsToTotalAndStaysBalanced() {
        let r = AIService.settle([line(1.99), line(2.00)], to: 4)
        XCTAssertEqual(r.status, .balanced)
        XCTAssertEqual(r.sum, 4)
        XCTAssertEqual(r.lines.count, 2, "no Unaccounted line for mere rounding")
    }

    func test_under_addsUnaccountedRemainder_notInflatedPrices() {
        // "two lighters" (€4) described against a €24 charge.
        let r = AIService.settle([line(4, qty: 2, desc: "Lighter")], to: 24)
        guard case .under(let remainder) = r.status else {
            return XCTFail("expected .under, got \(r.status)")
        }
        XCTAssertEqual(remainder, 20)
        XCTAssertEqual(r.lines.count, 2, "original item + Unaccounted line")
        XCTAssertEqual(r.lines.first?.amount, 4, "described item keeps its real price")
        XCTAssertEqual(r.lines.last?.description, "Unaccounted")
        XCTAssertEqual(r.lines.last?.amount, 20)
        XCTAssertNil(r.lines.last?.category)
        XCTAssertEqual(r.sum, 24)
    }

    func test_over_isReportedNotSilentlyScaled() {
        let r = AIService.settle([line(6), line(2)], to: 4)
        guard case .over(let excess) = r.status else {
            return XCTFail("expected .over, got \(r.status)")
        }
        XCTAssertEqual(excess, 4)
        XCTAssertEqual(r.lines.map(\.amount), [6, 2], "amounts untouched until the user decides")
        XCTAssertEqual(r.sum, 8)
    }

    func test_emptyAndNonPositiveTotal_balancedNoOp() {
        XCTAssertTrue(AIService.settle([], to: 4).lines.isEmpty)
        let zero = AIService.settle([line(2), line(2)], to: 0)
        XCTAssertEqual(zero.status, .balanced)
        XCTAssertEqual(zero.lines.map(\.amount), [2, 2])
    }

    // MARK: - proportionalScale: explicit "scale to fit"

    func test_scaleToFit_forcesExactSum() {
        let out = AIService.proportionalScale([line(6), line(2)], to: 4)
        XCTAssertEqual(out.reduce(Decimal(0)) { $0 + $1.amount }, 4)
        XCTAssertEqual(out.map(\.amount), [3, 1])
    }

    func test_scaleToFit_thenSettle_isBalanced() {
        let scaled = AIService.proportionalScale([line(6), line(2)], to: 4)
        XCTAssertEqual(AIService.settle(scaled, to: 4).status, .balanced)
    }

    func test_settle_preservesDescriptionsAndQuantities() {
        let r = AIService.settle(
            [ItemisedLine(description: "Lighter", quantity: 2, amount: 4, category: "Shopping")],
            to: 4)
        XCTAssertEqual(r.status, .balanced)
        XCTAssertEqual(r.lines.first?.description, "Lighter")
        XCTAssertEqual(r.lines.first?.quantity, 2)
        XCTAssertEqual(r.lines.first?.category, "Shopping")
        XCTAssertEqual(r.lines.first?.unitAmount, 2)
    }
}
