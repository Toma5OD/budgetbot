import XCTest
@testable import BudgetBot

final class AIServiceTests: XCTestCase {

    // MARK: - tool_use input extraction

    func test_toolUseInput_returnsInputForMatchingTool() throws {
        let json = """
        {
          "id": "msg_1",
          "type": "message",
          "role": "assistant",
          "model": "claude-sonnet-4-6",
          "stop_reason": "tool_use",
          "content": [
            {
              "type": "text",
              "text": "calling tool"
            },
            {
              "type": "tool_use",
              "id": "toolu_1",
              "name": "record_transactions",
              "input": {
                "drafts": [
                  {
                    "date": "2026-05-12",
                    "amount": -12.34,
                    "currency": "USD",
                    "payee": "Trader Joe's",
                    "suggested_category": "Groceries",
                    "confidence": 0.91
                  }
                ]
              }
            }
          ]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let inputData = try AIService.toolUseInput(in: data, expectedName: "record_transactions")

        struct Env: Decodable {
            struct Draft: Decodable {
                let amount: Double
                let payee: String
                let suggested_category: String?
            }
            let drafts: [Draft]
        }
        let env = try JSONDecoder().decode(Env.self, from: inputData)
        XCTAssertEqual(env.drafts.count, 1)
        XCTAssertEqual(env.drafts[0].payee, "Trader Joe's")
        XCTAssertEqual(env.drafts[0].amount, -12.34, accuracy: 0.0001)
        XCTAssertEqual(env.drafts[0].suggested_category, "Groceries")
    }

    func test_toolUseInput_throwsWhenToolMissing() throws {
        let json = """
        {
          "content": [{"type": "text", "text": "nope"}],
          "stop_reason": "end_turn"
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        XCTAssertThrowsError(try AIService.toolUseInput(in: data, expectedName: "record_transactions"))
    }

    func test_toolUseInput_throwsWhenNameMismatches() throws {
        let json = """
        {
          "content": [{
            "type": "tool_use",
            "name": "some_other_tool",
            "input": {"x": 1}
          }]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        XCTAssertThrowsError(try AIService.toolUseInput(in: data, expectedName: "record_transactions"))
    }

    // MARK: - Retry classification

    func test_isTransient_classifies429And5xxAndNetworkZero() {
        XCTAssertTrue(AIService.isTransient(.http(429, "rate limited")))
        XCTAssertTrue(AIService.isTransient(.http(500, "boom")))
        XCTAssertTrue(AIService.isTransient(.http(503, "down")))
        XCTAssertTrue(AIService.isTransient(.http(0,   "network")))
        XCTAssertFalse(AIService.isTransient(.http(400, "bad")))
        XCTAssertFalse(AIService.isTransient(.http(401, "auth")))
        XCTAssertFalse(AIService.isTransient(.http(404, "missing")))
        XCTAssertFalse(AIService.isTransient(.missingKey))
        XCTAssertFalse(AIService.isTransient(.empty))
    }

    func test_isTransientURL_picksUpNetworkErrors() {
        let timeout = URLError(.timedOut)
        let dns     = URLError(.dnsLookupFailed)
        let lost    = URLError(.networkConnectionLost)
        let bad     = URLError(.userAuthenticationRequired)

        XCTAssertTrue(AIService.isTransientURL(timeout))
        XCTAssertTrue(AIService.isTransientURL(dns))
        XCTAssertTrue(AIService.isTransientURL(lost))
        XCTAssertFalse(AIService.isTransientURL(bad))
    }

    func test_backoffSecondsGrowsAndStaysSmall() {
        // The exponential schedule should grow per attempt and never absurdly large
        // (we cap effectively at ~4s + jitter on the 4th attempt).
        let a1 = AIService.backoffSeconds(attempt: 1)
        let a2 = AIService.backoffSeconds(attempt: 2)
        let a3 = AIService.backoffSeconds(attempt: 3)
        let a4 = AIService.backoffSeconds(attempt: 4)
        XCTAssertGreaterThanOrEqual(a1, 0.5)
        XCTAssertGreaterThanOrEqual(a2, 1.0)
        XCTAssertGreaterThanOrEqual(a3, 2.0)
        XCTAssertGreaterThanOrEqual(a4, 4.0)
        XCTAssertLessThan(a4, 5.0)
    }
}
