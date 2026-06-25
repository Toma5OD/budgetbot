import XCTest
@testable import BudgetBot

final class YoloConfidenceTests: XCTestCase {

    private func draft(_ confidence: Double) -> ExtractedDraft {
        ExtractedDraft(date: Date(timeIntervalSince1970: 0),
                       amount: -10, currency: "EUR", payee: "Test",
                       lineItems: [], confidence: confidence)
    }

    func test_allConfident_whenEveryDraftClearsTheFloor() {
        XCTAssertTrue(CaptureQueueService.allConfident([draft(0.9), draft(0.8)]))
        XCTAssertTrue(CaptureQueueService.allConfident([draft(0.7)]), "floor is inclusive")
    }

    func test_oneLowConfidenceDraft_routesToReview() {
        // A single uncertain draft drops the batch out of YOLO auto-save.
        XCTAssertFalse(CaptureQueueService.allConfident([draft(0.9), draft(0.55)]))
        XCTAssertFalse(CaptureQueueService.allConfident([draft(0.4)]))
    }

    func test_emptyBatch_isVacuouslyConfident() {
        XCTAssertTrue(CaptureQueueService.allConfident([]))
    }
}
