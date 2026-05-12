import XCTest
@testable import BudgetBot

/// Exercises the real HTTP path of `AIService` via a `URLProtocol` stub.
/// Covers retry-on-429, retry-on-5xx, give-up-on-4xx, exhaustion, key validation,
/// and the happy-path tool_use → drafts decode.
final class AIServiceHTTPTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func service(backoffScale: Double = 0.001) -> AIService {
        AIService(
            model: "test",
            apiKey: "test-key-not-real",
            sessionConfiguration: .stubbed(),
            backoffScale: backoffScale
        )
    }

    // MARK: - Happy path

    func test_extract_decodes_toolUse_response() async throws {
let toolResponse = """
        {
          "id": "msg_1", "type": "message", "role": "assistant",
          "model": "test", "stop_reason": "tool_use",
          "content": [
            {
              "type": "tool_use",
              "id": "tool_1",
              "name": "record_transactions",
              "input": {
                "drafts": [
                  {"date": "2026-05-12", "amount": -3.50, "currency": "EUR",
                   "payee": "Costa", "suggested_category": "Coffee", "confidence": 0.94}
                ]
              }
            }
          ]
        }
        """
        StubURLProtocol.enqueueJSON(toolResponse)

        let drafts = try await service().extract(
            from: [.text("a coffee")],
            defaultCurrency: "EUR"
        )
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].payee, "Costa")
        XCTAssertEqual(drafts[0].amount, Decimal(string: "-3.5"))
        XCTAssertEqual(drafts[0].suggestedCategory, "Coffee")
    }

    func test_extract_sendsExpectedHeaders() async throws {
StubURLProtocol.enqueueJSON("""
        {"content": [{"type": "tool_use", "name": "record_transactions",
          "input": {"drafts": []}}], "stop_reason": "tool_use"}
        """)
        // drafts: [] -> service throws "couldn't find any" through the caller's
        // path, but the HTTP-layer test only cares about the request shape.
        _ = try? await service().extract(from: [.text("x")], defaultCurrency: "USD")

        guard let req = StubURLProtocol.capturedRequests.first else {
            return XCTFail("no request captured")
        }
        XCTAssertEqual(req.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(req.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-api-key"), "test-key-not-real")
        let betas = req.value(forHTTPHeaderField: "anthropic-beta") ?? ""
        XCTAssertTrue(betas.contains("prompt-caching-2024-07-31"))
    }

    // MARK: - Retries

    func test_retry_on429_thenSucceeds() async throws {
StubURLProtocol.enqueueJSON("{\"error\":\"rate limited\"}", status: 429)
        StubURLProtocol.enqueueJSON("""
        {"content": [{"type": "tool_use", "name": "record_transactions",
          "input": {"drafts": [{"amount": -1, "payee": "X", "confidence": 0.5}]}}],
         "stop_reason": "tool_use"}
        """)

        let drafts = try await service().extract(from: [.text("x")], defaultCurrency: "USD")
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(StubURLProtocol.capturedRequests.count, 2)
    }

    func test_retry_on5xx_thenSucceeds() async throws {
StubURLProtocol.enqueueJSON("{}", status: 502)
        StubURLProtocol.enqueueJSON("{}", status: 503)
        StubURLProtocol.enqueueJSON("""
        {"content": [{"type": "tool_use", "name": "record_transactions",
          "input": {"drafts": [{"amount": 1, "payee": "Y", "confidence": 0.6}]}}],
         "stop_reason": "tool_use"}
        """)

        let drafts = try await service().extract(from: [.text("x")], defaultCurrency: "USD")
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(StubURLProtocol.capturedRequests.count, 3)
    }

    func test_giveUp_on4xx_noRetry() async throws {
StubURLProtocol.enqueueJSON("{\"error\":\"bad request\"}", status: 400)

        do {
            _ = try await service().extract(from: [.text("x")], defaultCurrency: "USD")
            XCTFail("Expected throw on 400")
        } catch let err as AIService.AIError {
            if case .http(let code, _) = err {
                XCTAssertEqual(code, 400)
            } else {
                XCTFail("Expected .http error, got \(err)")
            }
        }
        XCTAssertEqual(StubURLProtocol.capturedRequests.count, 1,
                       "Must NOT retry on 4xx other than 429")
    }

    func test_giveUp_on401_unauthorized() async throws {
StubURLProtocol.enqueueJSON("{\"error\":\"auth\"}", status: 401)

        do {
            _ = try await service().extract(from: [.text("x")], defaultCurrency: "USD")
            XCTFail("Expected throw on 401")
        } catch let err as AIService.AIError {
            if case .http(let code, _) = err {
                XCTAssertEqual(code, 401)
            } else {
                XCTFail("Expected .http error, got \(err)")
            }
        }
        XCTAssertEqual(StubURLProtocol.capturedRequests.count, 1)
    }

    func test_exhaustsRetries_after4_5xx() async throws {
for _ in 0..<5 {
            StubURLProtocol.enqueueJSON("{}", status: 500)
        }
        do {
            _ = try await service().extract(from: [.text("x")], defaultCurrency: "USD")
            XCTFail("Expected throw after exhausting retries")
        } catch let err as AIService.AIError {
            if case .http(let code, _) = err {
                XCTAssertEqual(code, 500)
            } else {
                XCTFail("Expected .http, got \(err)")
            }
        }
        XCTAssertEqual(StubURLProtocol.capturedRequests.count, 4,
                       "Max 4 attempts in total")
    }

    // MARK: - Key validation

    func test_validateKey_returnsTrueOn200() async {
        StubURLProtocol.enqueueJSON("{}", status: 200)
        let ok = await AIService.validate(key: "x", sessionConfiguration: .stubbed())
        XCTAssertTrue(ok)
    }

    func test_validateKey_returnsFalseOn403() async {
        StubURLProtocol.enqueueJSON("{}", status: 403)
        let ok = await AIService.validate(key: "x", sessionConfiguration: .stubbed())
        XCTAssertFalse(ok)
    }

    func test_validateKey_returnsFalseOnEmpty() async {
        let ok = await AIService.validate(key: "  ")
        XCTAssertFalse(ok)
    }
}
