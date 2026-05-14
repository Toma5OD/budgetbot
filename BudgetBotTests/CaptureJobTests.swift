import XCTest
import SwiftData
@testable import BudgetBot

@MainActor
final class CaptureJobTests: XCTestCase {

    func test_freshJob_defaultsToQueued() {
        let job = CaptureJob()
        XCTAssertEqual(job.status, .queued)
        XCTAssertFalse(job.yoloMode)
        XCTAssertEqual(job.drafts.count, 0)
    }

    func test_draftsRoundTripThroughJSON() {
        let job = CaptureJob()
        let drafts: [ExtractedDraft] = [
            ExtractedDraft(date: .now, amount: -12.34, currency: "EUR",
                           payee: "Coffee", note: nil,
                           suggestedCategory: "Coffee",
                           accountHint: nil, lineItems: [], confidence: 0.9),
            ExtractedDraft(date: .now, amount: -7.10, currency: "EUR",
                           payee: "Bus", note: nil,
                           suggestedCategory: "Transport",
                           accountHint: nil, lineItems: [], confidence: 0.7)
        ]
        job.drafts = drafts
        XCTAssertNotNil(job.draftsJSON)
        XCTAssertEqual(job.drafts.count, 2)
        XCTAssertEqual(job.drafts.first?.payee, "Coffee")
        XCTAssertEqual(job.drafts.last?.suggestedCategory, "Transport")
    }

    func test_statusTransitions_areStable() throws {
        let container = try PersistenceController.makeInMemory()
        let ctx = container.mainContext

        let job = CaptureJob()
        ctx.insert(job)
        try ctx.save()

        job.status = .processing
        job.startedAt = .now
        try ctx.save()
        XCTAssertEqual(job.statusRaw, "processing")

        job.status = .awaitingReview
        try ctx.save()
        XCTAssertEqual(job.statusRaw, "awaitingReview")

        job.status = .committed
        try ctx.save()
        XCTAssertEqual(job.statusRaw, "committed")
    }

    func test_inputsCascadeOnJobDelete() throws {
        let container = try PersistenceController.makeInMemory()
        let ctx = container.mainContext

        let job = CaptureJob()
        ctx.insert(job)
        let att = Attachment(kind: .image, data: Data([0xFF, 0xD8]))
        att.captureJob = job
        ctx.insert(att)
        try ctx.save()

        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Attachment>()).count, 1)
        ctx.delete(job)
        try ctx.save()
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Attachment>()).count, 0,
                       "Cascade should drop the input attachment when the CaptureJob is deleted")
    }
}
