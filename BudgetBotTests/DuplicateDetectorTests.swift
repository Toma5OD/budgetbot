import XCTest
@testable import BudgetBot

final class DuplicateDetectorTests: XCTestCase {

    private func draft(_ amount: Decimal, _ payee: String, daysAgo: Int = 0) -> ExtractedDraft {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return ExtractedDraft(
            date: date, amount: amount, currency: "USD",
            payee: payee, note: nil, suggestedCategory: nil,
            accountHint: nil, lineItems: [], confidence: 0.9
        )
    }

    private func existing(_ amount: Decimal, _ payee: String, daysAgo: Int) -> DuplicateDetector.Existing {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return .init(id: UUID(), date: date, amount: amount, payee: payee)
    }

    func test_exactMatchFlagged() {
        let det = DuplicateDetector()
        let d = draft(-12.34, "Trader Joe's", daysAgo: 1)
        let e = existing(-12.34, "Trader Joe's", daysAgo: 1)
        XCTAssertEqual(det.duplicates(for: d, against: [e]).count, 1)
    }

    func test_normalisedPayeeMatch_caseAndPunctuation() {
        let det = DuplicateDetector()
        let d = draft(-5, "Trader Joe's", daysAgo: 0)
        let e = existing(-5, "TRADER JOES", daysAgo: 0)
        XCTAssertEqual(det.duplicates(for: d, against: [e]).count, 1)
    }

    func test_withinDateWindow() {
        let det = DuplicateDetector(dateWindowDays: 3)
        let d = draft(-10, "Costa", daysAgo: 0)
        let e = existing(-10, "Costa", daysAgo: 3)
        XCTAssertEqual(det.duplicates(for: d, against: [e]).count, 1)
    }

    func test_outsideDateWindowIsNotDuplicate() {
        let det = DuplicateDetector(dateWindowDays: 3)
        let d = draft(-10, "Costa", daysAgo: 0)
        let e = existing(-10, "Costa", daysAgo: 7)
        XCTAssertTrue(det.duplicates(for: d, against: [e]).isEmpty)
    }

    func test_signMismatchIsNotDuplicate() {
        // Refund vs expense at same payee/amount — different transactions.
        let det = DuplicateDetector()
        let d = draft(10, "Lidl", daysAgo: 0)
        let e = existing(-10, "Lidl", daysAgo: 0)
        XCTAssertTrue(det.duplicates(for: d, against: [e]).isEmpty)
    }

    func test_smallAmountToleranceWithinPercent() {
        // 1% of 1000 = 10; existing 1009 should match a 1000 draft.
        let det = DuplicateDetector(amountTolerancePct: Decimal(string: "0.01")!)
        let d = draft(-1000, "Rent", daysAgo: 0)
        let e = existing(-1009, "Rent", daysAgo: 0)
        XCTAssertEqual(det.duplicates(for: d, against: [e]).count, 1)
    }

    func test_largeAmountDifferenceIsNotDuplicate() {
        let det = DuplicateDetector(amountTolerancePct: Decimal(string: "0.01")!)
        let d = draft(-1000, "Rent", daysAgo: 0)
        let e = existing(-1500, "Rent", daysAgo: 0)
        XCTAssertTrue(det.duplicates(for: d, against: [e]).isEmpty)
    }

    func test_payeeMustMatchAfterNormalisation() {
        let det = DuplicateDetector()
        let d = draft(-10, "Tesco", daysAgo: 0)
        let e = existing(-10, "Sainsbury", daysAgo: 0)
        XCTAssertTrue(det.duplicates(for: d, against: [e]).isEmpty)
    }

    // MARK: - Normalisation helper

    func test_normaliseStripsPunctuation() {
        XCTAssertEqual(DuplicateDetector.normalise("Joe's, Inc."), "joesinc")
        XCTAssertEqual(DuplicateDetector.normalise("  AMAZON.com  "), "amazoncom")
        XCTAssertEqual(DuplicateDetector.normalise("Tëscó"), "tëscó".lowercased().filter { $0.isLetter || $0.isNumber })
    }
}
