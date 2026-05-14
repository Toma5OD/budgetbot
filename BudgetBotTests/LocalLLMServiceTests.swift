import XCTest
@testable import BudgetBot

@MainActor
final class LocalLLMServiceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "BudgetBot.preferOnDeviceAI")
    }

    func test_isPreferred_defaultsOff() {
        XCTAssertFalse(LocalLLMService.shared.isPreferred,
                       "Default off — most users either lack the hardware or run pre-iOS-26")
    }

    func test_isPreferred_persistsAcrossReads() {
        LocalLLMService.shared.isPreferred = true
        XCTAssertTrue(LocalLLMService.shared.isPreferred)
        LocalLLMService.shared.isPreferred = false
        XCTAssertFalse(LocalLLMService.shared.isPreferred)
    }

    func test_availability_isFalseOnTestRuntime() {
        // The test bundle runs on a simulator that doesn't have Apple
        // Intelligence wired up. We don't assert true/false — we just
        // assert the call doesn't crash and returns a sensible reason.
        let avail = LocalLLMService.shared.isAvailable
        let reason = LocalLLMService.shared.availabilityReason
        if !avail {
            // One of the off-states is reasonable.
            switch reason {
            case .iosTooOld, .deviceNotEligible,
                 .appleIntelligenceDisabled, .modelDownloading, .other:
                break
            case .available:
                XCTFail("isAvailable=false but availabilityReason=.available — contradictory")
            }
        }
    }

    func test_generate_throwsWhenUnavailable() async throws {
        // If FM happens to be available in this runtime, skip — the
        // assertion only applies to the off-state.
        guard !LocalLLMService.shared.isAvailable else {
            throw XCTSkip("Foundation Models is somehow available in this test runtime")
        }
        do {
            _ = try await LocalLLMService.shared.generate("Hello")
            XCTFail("Expected throw when FM is unavailable")
        } catch let err as LocalLLMError {
            if case .unavailable = err {} else {
                XCTFail("Expected .unavailable got \(err)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func test_availabilityReason_messagesAreUserFacing() {
        // Spot-check that each reason has a non-empty, sentence-shaped
        // user-facing message — these end up in the Settings subtitle.
        let cases: [LocalLLMService.AvailabilityReason] = [
            .available, .iosTooOld, .deviceNotEligible,
            .appleIntelligenceDisabled, .modelDownloading,
            .other("test")
        ]
        for c in cases {
            let msg = c.userFacingMessage
            XCTAssertFalse(msg.isEmpty)
            // Sentence-shaped: starts with capital letter.
            XCTAssertEqual(msg.first?.isUppercase ?? false, true,
                           "Subtitle should start with a capital letter: \(msg)")
        }
    }
}
