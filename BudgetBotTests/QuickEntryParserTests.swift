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

    // MARK: - Dates

    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    func test_noDate_isNil() {
        XCTAssertNil(QuickEntryParser.parse("haircut €30", now: now)?.date)
    }

    func test_yesterday() {
        let e = QuickEntryParser.parse("coffee €4 yesterday", now: now)
        XCTAssertEqual(e?.payee, "Coffee")
        XCTAssertEqual(e?.amount, 4)
        XCTAssertEqual(e?.date, Calendar.current.date(byAdding: .day, value: -1, to: now))
    }

    func test_nDaysAgo() {
        let e = QuickEntryParser.parse("lunch €12 2 days ago", now: now)
        XCTAssertEqual(e?.amount, 12)
        XCTAssertEqual(e?.date, Calendar.current.date(byAdding: .day, value: -2, to: now))
    }

    func test_today_stripsWordFromPayee() {
        let e = QuickEntryParser.parse("today milk €3", now: now)
        XCTAssertEqual(e?.payee, "Milk")
        XCTAssertEqual(e?.date, now)
    }
}

final class ReceiptDateTests: XCTestCase {

    func test_dateOnly() {
        let d = AIService.parseReceiptDate("2026-06-25")
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        XCTAssertEqual(c.year, 2026); XCTAssertEqual(c.month, 6); XCTAssertEqual(c.day, 25)
    }

    func test_dateTime_keepsTime() {
        let d = AIService.parseReceiptDate("2026-06-25T14:30")
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        XCTAssertEqual(c.hour, 14); XCTAssertEqual(c.minute, 30)
    }

    func test_missingOrGarbage_isNow() {
        let now = Date().timeIntervalSince1970
        XCTAssertEqual(AIService.parseReceiptDate(nil).timeIntervalSince1970, now, accuracy: 5)
        XCTAssertEqual(AIService.parseReceiptDate("not a date").timeIntervalSince1970, now, accuracy: 5)
    }

    private let fixedNow = Date(timeIntervalSince1970: 1_750_000_000)   // mid-2025

    func test_futureDate_clampsToNow() {
        // A receipt can't be from the future — a forward-dated row (clock
        // skew, a misread year) falls back to now instead of parking spend
        // in a month that hasn't happened.
        XCTAssertEqual(AIService.parseReceiptDate("2999-01-01", now: fixedNow), fixedNow)
    }

    func test_pastDate_keptAsIs() {
        let d = AIService.parseReceiptDate("2020-03-04", now: fixedNow)
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        XCTAssertEqual(c.year, 2020); XCTAssertEqual(c.month, 3); XCTAssertEqual(c.day, 4)
    }

    func test_isoDay_isTenCharsAndYearPrefixed() {
        let s = AIService.isoDay(fixedNow)
        XCTAssertEqual(s.count, 10)
        XCTAssertEqual(String(s.prefix(4)), "2025")
    }
}

final class DraftReviewSignalTests: XCTestCase {

    private func draft(confidence: Double, questions: [String]?) -> ExtractedDraft {
        ExtractedDraft(date: Date(), amount: -9.24, currency: "EUR", payee: "SuperValu",
                       lineItems: [], confidence: confidence, questions: questions)
    }

    func test_confidentNoQuestions_doesNotNeedReview() {
        XCTAssertFalse(draft(confidence: 0.9, questions: nil).needsReview())
        XCTAssertFalse(draft(confidence: 0.9, questions: []).needsReview())
    }

    func test_lowConfidence_needsReview() {
        XCTAssertTrue(draft(confidence: 0.5, questions: nil).needsReview())
    }

    func test_questionsForceReview_evenWhenConfident() {
        let d = draft(confidence: 0.95, questions: ["Some item prices were unreadable — please check."])
        XCTAssertTrue(d.needsReview())
        XCTAssertEqual(d.questionList.count, 1)
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
