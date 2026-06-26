import XCTest
@testable import BudgetBot

final class YoloConfidenceTests: XCTestCase {

    private func draft(_ confidence: Double, questions: [String]? = nil) -> ExtractedDraft {
        ExtractedDraft(date: Date(timeIntervalSince1970: 0),
                       amount: -10, currency: "EUR", payee: "Test",
                       lineItems: [], confidence: confidence, questions: questions)
    }

    func test_allClear_whenEveryDraftClearsTheFloor() {
        XCTAssertTrue(CaptureQueueService.allClear([draft(0.9), draft(0.8)]))
        XCTAssertTrue(CaptureQueueService.allClear([draft(0.7)]), "floor is inclusive")
    }

    func test_oneLowConfidenceDraft_routesToReview() {
        // A single uncertain draft drops the batch out of YOLO auto-save.
        XCTAssertFalse(CaptureQueueService.allClear([draft(0.9), draft(0.55)]))
        XCTAssertFalse(CaptureQueueService.allClear([draft(0.4)]))
    }

    func test_questionsRouteToReview_evenWhenConfident() {
        // The AI can be "confident" in its guess but still flag something it
        // couldn't read. Any open question must pull the draft into review.
        let q = draft(0.95, questions: ["Couldn't read the total — is it €9.24?"])
        XCTAssertTrue(q.needsReview())
        XCTAssertFalse(CaptureQueueService.allClear([draft(0.9), q]))
    }

    func test_emptyQuestions_doesNotRoute() {
        XCTAssertFalse(draft(0.9, questions: []).needsReview())
        XCTAssertTrue(CaptureQueueService.allClear([draft(0.9, questions: [])]))
    }

    func test_emptyBatch_isVacuouslyClear() {
        XCTAssertTrue(CaptureQueueService.allClear([]))
    }
}
