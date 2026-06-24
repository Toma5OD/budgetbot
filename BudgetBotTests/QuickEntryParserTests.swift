import XCTest
@testable import BudgetBot

final class QuickEntryParserTests: XCTestCase {

    func test_simpleWithCurrency() {
        let e = QuickEntryParser.parse("haircut €30")
        XCTAssertEqual(e?.payee, "Haircut")
        XCTAssertEqual(e?.amount, 30)
        XCTAssertEqual(e?.quantity, 1)
    }

    func test_quantityAndCurrency() {
        let e = QuickEntryParser.parse("2 coffees for €13")
        XCTAssertEqual(e?.payee, "Coffees")
        XCTAssertEqual(e?.amount, 13)
        XCTAssertEqual(e?.quantity, 2)
    }

    func test_decimalNoCurrency() {
        let e = QuickEntryParser.parse("coffee 4.50")
        XCTAssertEqual(e?.payee, "Coffee")
        XCTAssertEqual(e?.amount, Decimal(string: "4.50"))
        XCTAssertEqual(e?.quantity, 1)
    }

    func test_amountFirst_isNotMistakenForQuantity() {
        let e = QuickEntryParser.parse("30 haircut")
        XCTAssertEqual(e?.amount, 30)
        XCTAssertEqual(e?.quantity, 1)
        XCTAssertEqual(e?.payee, "Haircut")
    }

    func test_dollarSign_and_threeItems() {
        XCTAssertEqual(QuickEntryParser.parse("$5 sandwich")?.amount, 5)
        let beers = QuickEntryParser.parse("3 beers 18")
        XCTAssertEqual(beers?.quantity, 3)
        XCTAssertEqual(beers?.amount, 18)
        XCTAssertEqual(beers?.payee, "Beers")
    }

    func test_commaDecimal() {
        XCTAssertEqual(QuickEntryParser.parse("lunch 12,99")?.amount, Decimal(string: "12.99"))
    }

    func test_noAmount_returnsNil() {
        XCTAssertNil(QuickEntryParser.parse("just a note"))
        XCTAssertNil(QuickEntryParser.parse(""))
    }

    func test_amountOnly_payeeFallsBack() {
        let e = QuickEntryParser.parse("€20")
        XCTAssertEqual(e?.amount, 20)
        XCTAssertEqual(e?.payee, "Expense")
    }
}

final class ExpandQuantitiesTests: XCTestCase {

    private func line(_ amount: Decimal, qty: Int) -> ItemisedLine {
        ItemisedLine(description: "Coffee", quantity: qty, amount: amount, category: nil)
    }

    func test_evenSplit() {
        let out = AIService.expandQuantities([line(13, qty: 2)])
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out.map(\.amount), [Decimal(string: "6.50"), Decimal(string: "6.50")])
        XCTAssertTrue(out.allSatisfy { $0.quantity == 1 && $0.description == "Coffee" })
    }

    func test_residualOnFirst_sumPreserved() {
        let out = AIService.expandQuantities([line(10, qty: 3)])
        XCTAssertEqual(out.count, 3)
        XCTAssertEqual(out.reduce(Decimal(0)) { $0 + $1.amount }, 10)
        XCTAssertEqual(out[0].amount, Decimal(string: "3.34"))
    }

    func test_singleQuantity_untouched() {
        let out = AIService.expandQuantities([line(4, qty: 1)])
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first?.amount, 4)
    }
}
