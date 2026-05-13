import XCTest
@testable import BudgetBot

@MainActor
final class PaymentMethodMatchingTests: XCTestCase {

    private func draft(currency: String = "EUR",
                       payment: ExtractedDraft.PaymentMethod = .unknown,
                       hint: String? = nil) -> ExtractedDraft {
        ExtractedDraft(
            date: .now, amount: -10, currency: currency,
            payee: "X", note: nil, suggestedCategory: nil,
            accountHint: hint, paymentMethod: payment,
            lineItems: [], confidence: 0.9
        )
    }

    func test_cashHint_picksCashAccount() {
        let wallet = Account(name: "Wallet", kind: .cash, currency: "EUR")
        let bank   = Account(name: "Bank",   kind: .bank, currency: "EUR")
        let result = CaptureViewModel.matchAccount(
            for: draft(payment: .cash),
            in: [bank, wallet]
        )
        XCTAssertEqual(result?.name, "Wallet")
    }

    func test_cardHint_prefersCardAccountInSameCurrency() {
        let eurBank = Account(name: "Revolut EUR", kind: .bank, currency: "EUR")
        let usdBank = Account(name: "Chase USD",   kind: .bank, currency: "USD")
        let result = CaptureViewModel.matchAccount(
            for: draft(currency: "USD", payment: .card),
            in: [eurBank, usdBank]
        )
        XCTAssertEqual(result?.name, "Chase USD")
    }

    func test_accountHint_winsOverPaymentMethod() {
        let wallet  = Account(name: "Wallet",  kind: .cash, currency: "EUR")
        let revolut = Account(name: "Revolut", kind: .bank, currency: "EUR")
        // Cash hint says cash, but AI also gave an explicit account hint of Revolut.
        let result = CaptureViewModel.matchAccount(
            for: draft(payment: .cash, hint: "Revolut"),
            in: [wallet, revolut]
        )
        XCTAssertEqual(result?.name, "Revolut",
                       "Explicit account_hint must beat payment_method heuristic")
    }

    func test_unknownPayment_returnsNilSoCallerUsesDefault() {
        let wallet = Account(name: "Wallet", kind: .cash, currency: "EUR")
        XCTAssertNil(CaptureViewModel.matchAccount(
            for: draft(payment: .unknown),
            in: [wallet]
        ))
    }

    func test_cardHint_fallsBackWhenNoMatchingCurrencyAccount() {
        // No bank/credit account in the draft currency → returns nil so caller
        // picks the user's default.
        let wallet = Account(name: "Wallet", kind: .cash, currency: "EUR")
        XCTAssertNil(CaptureViewModel.matchAccount(
            for: draft(currency: "USD", payment: .card),
            in: [wallet]
        ))
    }
}
