import XCTest
@testable import BudgetBot

@MainActor
final class PaymentDescriptionTests: XCTestCase {

    private func make(method: Transaction.PaymentMethod,
                      brand: String? = nil,
                      last4: String? = nil) -> Transaction {
        Transaction(
            date: .now,
            amount: -10,
            currency: "EUR",
            payee: "X",
            paymentMethod: method,
            cardBrand: brand,
            cardLast4: last4
        )
    }

    func test_cashAlwaysShowsCash() {
        XCTAssertEqual(make(method: .cash).paymentDescription, "Cash")
        // Even if a bogus brand snuck in, cash wins.
        XCTAssertEqual(make(method: .cash, brand: "Visa").paymentDescription, "Cash")
    }

    func test_cardWithBrandAndLast4_rendersBrandAndDots() {
        let t = make(method: .card, brand: "Visa", last4: "4242")
        XCTAssertEqual(t.paymentDescription, "Visa ••4242")
    }

    func test_cardWithBrandOnly() {
        XCTAssertEqual(make(method: .card, brand: "Mastercard").paymentDescription,
                       "Mastercard")
    }

    func test_cardWithLast4Only_fallsBackToGenericCard() {
        XCTAssertEqual(make(method: .card, last4: "1111").paymentDescription,
                       "Card ••1111")
    }

    func test_cardWithNothing_rendersCard() {
        XCTAssertEqual(make(method: .card).paymentDescription, "Card")
    }

    func test_unknownMethod_butBrandKnown_stillRendersBrand() {
        // If extraction was uncertain about cash-vs-card but found "Visa 4242",
        // we still want the user-visible row to surface what we know.
        let t = make(method: .unknown, brand: "Visa", last4: "4242")
        XCTAssertEqual(t.paymentDescription, "Visa ••4242")
    }

    func test_unknownMethod_andNothingKnown_rendersEmDash() {
        XCTAssertEqual(make(method: .unknown).paymentDescription, "—")
    }
}
