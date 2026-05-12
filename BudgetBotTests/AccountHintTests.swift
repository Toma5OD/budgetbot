import XCTest
@testable import BudgetBot

@MainActor
final class AccountHintTests: XCTestCase {

    private func draft(_ hint: String?) -> ExtractedDraft {
        ExtractedDraft(date: .now, amount: -10, currency: "USD",
                       payee: "X", note: nil, suggestedCategory: nil,
                       accountHint: hint, lineItems: [], confidence: 0.9)
    }

    func test_nilHintReturnsNil() {
        let cash = Account(name: "Wallet", kind: .cash)
        let bank = Account(name: "Chase Checking", kind: .bank)
        XCTAssertNil(CaptureViewModel.matchAccount(for: draft(nil), in: [cash, bank]))
    }

    func test_exactNameMatch() {
        let cash = Account(name: "Wallet", kind: .cash)
        let bank = Account(name: "Chase Checking", kind: .bank)
        let result = CaptureViewModel.matchAccount(for: draft("Chase Checking"), in: [cash, bank])
        XCTAssertEqual(result?.name, "Chase Checking")
    }

    func test_caseInsensitiveExactMatch() {
        let bank = Account(name: "Chase Checking", kind: .bank)
        let result = CaptureViewModel.matchAccount(for: draft("CHASE CHECKING"), in: [bank])
        XCTAssertEqual(result?.name, "Chase Checking")
    }

    func test_partialMatchHintContainsName() {
        let bank = Account(name: "Chase", kind: .bank)
        let result = CaptureViewModel.matchAccount(for: draft("Chase Visa 4242"), in: [bank])
        XCTAssertEqual(result?.name, "Chase")
    }

    func test_partialMatchNameContainsHint() {
        let bank = Account(name: "Chase Checking", kind: .bank)
        let result = CaptureViewModel.matchAccount(for: draft("Chase"), in: [bank])
        XCTAssertEqual(result?.name, "Chase Checking")
    }

    func test_emptyAccountListReturnsNil() {
        XCTAssertNil(CaptureViewModel.matchAccount(for: draft("Anything"), in: []))
    }
}
