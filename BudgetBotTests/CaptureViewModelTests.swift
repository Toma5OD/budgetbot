import XCTest
@testable import BudgetBot

final class CaptureViewModelTests: XCTestCase {

    private func makeCategories() -> [TxCategory] {
        TxCategory.defaults.map { TxCategory(name: $0.0, kind: $0.1, emoji: $0.2) }
    }

    func test_matchCategory_exactName() {
        let cats = makeCategories()
        let d = ExtractedDraft(date: .now, amount: -10, currency: "USD",
                               payee: "Tesco", note: nil,
                               suggestedCategory: "Groceries", lineItems: [], confidence: 0.9)
        let cat = CaptureViewModel.matchCategory(for: d, in: cats)
        XCTAssertEqual(cat?.name, "Groceries")
    }

    func test_matchCategory_caseInsensitive() {
        let cats = makeCategories()
        let d = ExtractedDraft(date: .now, amount: -10, currency: "USD",
                               payee: "Starbucks", note: nil,
                               suggestedCategory: "coffee", lineItems: [], confidence: 0.9)
        let cat = CaptureViewModel.matchCategory(for: d, in: cats)
        XCTAssertEqual(cat?.name, "Coffee")
    }

    func test_matchCategory_fuzzyContains() {
        let cats = makeCategories()
        let d = ExtractedDraft(date: .now, amount: -10, currency: "USD",
                               payee: "Shell", note: nil,
                               suggestedCategory: "fuel station", lineItems: [], confidence: 0.9)
        let cat = CaptureViewModel.matchCategory(for: d, in: cats)
        XCTAssertEqual(cat?.name, "Fuel")
    }

    func test_matchCategory_unknownFallsBackByKind() {
        let cats = makeCategories()
        let expense = ExtractedDraft(date: .now, amount: -10, currency: "USD",
                                     payee: "??", note: nil,
                                     suggestedCategory: "definitely not a category",
                                     lineItems: [], confidence: 0.4)
        let income = ExtractedDraft(date: .now, amount: 100, currency: "USD",
                                    payee: "??", note: nil,
                                    suggestedCategory: nil,
                                    lineItems: [], confidence: 0.4)
        let e = CaptureViewModel.matchCategory(for: expense, in: cats)
        let i = CaptureViewModel.matchCategory(for: income,  in: cats)
        XCTAssertEqual(e?.kind, .expense)
        XCTAssertEqual(i?.kind, .income)
    }
}
