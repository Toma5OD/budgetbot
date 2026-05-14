import XCTest
@testable import BudgetBot

/// Smoke-tests the wire format we expect the model to emit via tool_use.
final class ExtractedDraftWireTests: XCTestCase {

    func test_decodesMinimalDraft() throws {
        let json = """
        { "amount": -5.5, "payee": "Joe's", "confidence": 0.6 }
        """
        let w = try JSONDecoder().decode(ExtractedDraftWire.self, from: Data(json.utf8))
        XCTAssertEqual(w.amount, -5.5)
        XCTAssertEqual(w.payee, "Joe's")
        XCTAssertEqual(w.confidence, 0.6)
        XCTAssertNil(w.date)
        XCTAssertNil(w.line_items)
    }

    func test_decodesFullDraftWithLineItems() throws {
        let json = """
        {
          "date": "2026-04-30",
          "amount": -23.4,
          "currency": "EUR",
          "payee": "Lidl",
          "note": "weekly groceries",
          "suggested_category": "Groceries",
          "line_items": [
            {"description": "Bread", "amount": 2.2},
            {"description": "Milk",  "amount": 1.5}
          ],
          "confidence": 0.93
        }
        """
        let w = try JSONDecoder().decode(ExtractedDraftWire.self, from: Data(json.utf8))
        XCTAssertEqual(w.currency, "EUR")
        XCTAssertEqual(w.line_items?.count, 2)
        XCTAssertEqual(w.line_items?.first?.description, "Bread")
    }

    func test_decodesCardBrandAndLast4() throws {
        let json = """
        {
          "amount": -42.00,
          "payee": "Tesco",
          "payment_method": "card",
          "card_brand": "Visa",
          "card_last4": "4242",
          "confidence": 0.95
        }
        """
        let w = try JSONDecoder().decode(ExtractedDraftWire.self, from: Data(json.utf8))
        XCTAssertEqual(w.payment_method, "card")
        XCTAssertEqual(w.card_brand, "Visa")
        XCTAssertEqual(w.card_last4, "4242")
    }

    func test_decodesWithMissingCardFields() throws {
        // Model is allowed to omit card_brand / card_last4 when the receipt
        // didn't show them. Decoder must not throw.
        let json = """
        { "amount": -3.0, "payee": "Bus", "payment_method": "cash", "confidence": 0.8 }
        """
        let w = try JSONDecoder().decode(ExtractedDraftWire.self, from: Data(json.utf8))
        XCTAssertNil(w.card_brand)
        XCTAssertNil(w.card_last4)
    }

    func test_decodesRecommendationsEnvelope() throws {
        let json = """
        {
          "recommendations": [
            {"kind": "silly",   "title": "Coffee runs", "body": "lots of coffee", "estimated_monthly_savings": 80},
            {"kind": "savings", "title": "Auto-transfer", "body": "set up $200/mo"}
          ]
        }
        """
        let env = try JSONDecoder().decode(RecommendationsWire.self, from: Data(json.utf8))
        XCTAssertEqual(env.recommendations.count, 2)
        XCTAssertEqual(env.recommendations[0].estimated_monthly_savings, 80)
        XCTAssertNil(env.recommendations[1].estimated_monthly_savings)
    }
}
