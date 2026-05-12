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
