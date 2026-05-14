import XCTest
@testable import BudgetBot

final class CritiqueServiceTests: XCTestCase {

    // MARK: - Apply: amounts, dates, categories, currency, payment

    private func makeDrafts() -> [ExtractedDraft] {
        [
            ExtractedDraft(
                date: Date(timeIntervalSince1970: 1_700_000_000),
                amount: -25.00, currency: "EUR",
                payee: "Costa", note: nil,
                suggestedCategory: "Coffee",
                newCategory: nil,
                accountHint: nil,
                paymentMethod: .card,
                lineItems: [], confidence: 0.85
            ),
            ExtractedDraft(
                date: Date(timeIntervalSince1970: 1_700_086_400),
                amount: -10.00, currency: "EUR",
                payee: "Tesco", note: nil,
                suggestedCategory: "Other Expense",
                newCategory: nil,
                accountHint: nil,
                paymentMethod: .unknown,
                lineItems: [], confidence: 0.7
            )
        ]
    }

    func test_apply_amountCorrection_updatesValueAndAppendsNote() {
        let drafts = makeDrafts()
        let correction = CritiqueCorrection(
            draftIndex: 0,
            field: "amount",
            newValue: "-52.00",
            rationale: "Receipt total 52.00, draft has 25.00 — misread 5 as 2"
        )
        let out = CritiqueApplier.apply([correction], to: drafts)
        XCTAssertEqual(out[0].amount, Decimal(string: "-52.00"))
        XCTAssertTrue(out[0].note?.contains("Critique") == true)
        XCTAssertTrue(out[0].note?.contains("misread") == true)
    }

    func test_apply_categoryCorrection() {
        let drafts = makeDrafts()
        let correction = CritiqueCorrection(
            draftIndex: 1,
            field: "suggested_category",
            newValue: "Groceries",
            rationale: "Tesco is a grocery store"
        )
        let out = CritiqueApplier.apply([correction], to: drafts)
        XCTAssertEqual(out[1].suggestedCategory, "Groceries")
    }

    func test_apply_dateCorrection_parsesISO() {
        let drafts = makeDrafts()
        let correction = CritiqueCorrection(
            draftIndex: 0,
            field: "date",
            newValue: "2026-05-12",
            rationale: "Receipt shows May 12 2026"
        )
        let out = CritiqueApplier.apply([correction], to: drafts)
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day], from: out[0].date)
        XCTAssertEqual(comps.year,  2026)
        XCTAssertEqual(comps.month, 5)
        XCTAssertEqual(comps.day,   12)
    }

    func test_apply_currencyCorrection_uppercases() {
        let drafts = makeDrafts()
        let correction = CritiqueCorrection(
            draftIndex: 0,
            field: "currency",
            newValue: "gbp",
            rationale: "£ sign misread as €"
        )
        let out = CritiqueApplier.apply([correction], to: drafts)
        XCTAssertEqual(out[0].currency, "GBP")
    }

    func test_apply_paymentMethodCorrection() {
        let drafts = makeDrafts()
        let correction = CritiqueCorrection(
            draftIndex: 1,
            field: "payment_method",
            newValue: "cash",
            rationale: "Receipt says CASH"
        )
        let out = CritiqueApplier.apply([correction], to: drafts)
        XCTAssertEqual(out[1].paymentMethod, .cash)
    }

    func test_apply_unknownField_isIgnored() {
        let drafts = makeDrafts()
        let correction = CritiqueCorrection(
            draftIndex: 0,
            field: "merchant_phone",  // not a thing we know about
            newValue: "+353 1 555",
            rationale: "Random"
        )
        let out = CritiqueApplier.apply([correction], to: drafts)
        XCTAssertEqual(out[0].amount, drafts[0].amount, "Untouched")
        XCTAssertNil(out[0].note, "No rationale appended for unknown fields")
    }

    func test_apply_outOfRangeIndex_isIgnored() {
        let drafts = makeDrafts()
        let correction = CritiqueCorrection(
            draftIndex: 99,
            field: "amount",
            newValue: "-1.00",
            rationale: "..."
        )
        let out = CritiqueApplier.apply([correction], to: drafts)
        XCTAssertEqual(out.count, drafts.count)
        XCTAssertEqual(out[0].amount, drafts[0].amount)
        XCTAssertEqual(out[1].amount, drafts[1].amount)
    }

    func test_apply_multipleCorrections_compound() {
        let drafts = makeDrafts()
        let corrections = [
            CritiqueCorrection(draftIndex: 0, field: "amount",
                               newValue: "-52", rationale: "fix amount"),
            CritiqueCorrection(draftIndex: 1, field: "suggested_category",
                               newValue: "Groceries", rationale: "fix cat"),
            CritiqueCorrection(draftIndex: 1, field: "payment_method",
                               newValue: "card", rationale: "fix pm")
        ]
        let out = CritiqueApplier.apply(corrections, to: drafts)
        XCTAssertEqual(out[0].amount, -52)
        XCTAssertEqual(out[1].suggestedCategory, "Groceries")
        XCTAssertEqual(out[1].paymentMethod, .card)
        // Both rationales appended on draft 1's note
        let note1 = out[1].note ?? ""
        XCTAssertTrue(note1.contains("fix cat"))
        XCTAssertTrue(note1.contains("fix pm"))
    }

    func test_apply_noteField_replacesAndSkipsAutoAppend() {
        let drafts = makeDrafts()
        let correction = CritiqueCorrection(
            draftIndex: 0,
            field: "note",
            newValue: "Tip included",
            rationale: "Tip line printed on receipt"
        )
        let out = CritiqueApplier.apply([correction], to: drafts)
        XCTAssertEqual(out[0].note, "Tip included",
                       "When the AI corrects the note field, replace it cleanly")
        XCTAssertFalse(out[0].note?.contains("Critique") ?? false,
                       "Should not auto-append rationale when the field IS note")
    }

    // MARK: - Wire-format decoding

    func test_decodes_emptyCorrections_payload() throws {
        let json = #"""
        { "corrections": [] }
        """#
        let result = try JSONDecoder().decode(CritiqueResult.self, from: Data(json.utf8))
        XCTAssertTrue(result.corrections.isEmpty)
    }

    func test_decodes_realisticPayload_withSnakeCase() throws {
        let json = #"""
        {
          "corrections": [
            {
              "draft_index": 0,
              "field": "amount",
              "new_value": "-52.10",
              "rationale": "Misread 5 as 2 in tens place"
            }
          ]
        }
        """#
        let result = try JSONDecoder().decode(CritiqueResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.corrections.count, 1)
        XCTAssertEqual(result.corrections[0].draftIndex, 0)
        XCTAssertEqual(result.corrections[0].field, "amount")
        XCTAssertEqual(result.corrections[0].newValue, "-52.10")
    }
}
