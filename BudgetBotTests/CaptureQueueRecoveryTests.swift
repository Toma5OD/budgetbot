import XCTest
import SwiftData
@testable import BudgetBot

@MainActor
final class CaptureQueueRecoveryTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        try PersistenceController.makeInMemory()
    }

    func test_orphanedProcessingJob_resetToQueued() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        // Simulate a job that was mid-extraction when the app was
        // killed: it's stuck in `.processing` with nothing in flight.
        let job = CaptureJob()
        job.status = .processing
        job.startedAt = .now
        ctx.insert(job)
        try ctx.save()

        let service = CaptureQueueService(container: container)
        service.recoverOrphanedJobs()

        let fetched = try ctx.fetch(FetchDescriptor<CaptureJob>())
        XCTAssertEqual(fetched.first?.status, .queued,
                       "An orphaned .processing job must be reset to .queued so it retries")
        XCTAssertNil(fetched.first?.startedAt,
                     "startedAt should be cleared on recovery")
    }

    func test_recovery_leavesQueuedJobsAlone() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let job = CaptureJob()
        job.status = .queued
        ctx.insert(job)
        try ctx.save()

        let service = CaptureQueueService(container: container)
        service.recoverOrphanedJobs()

        let fetched = try ctx.fetch(FetchDescriptor<CaptureJob>())
        XCTAssertEqual(fetched.first?.status, .queued)
    }

    func test_recovery_leavesCommittedAndFailedJobsAlone() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let committed = CaptureJob(); committed.status = .committed
        let failed = CaptureJob();    failed.status = .failed
        ctx.insert(committed); ctx.insert(failed)
        try ctx.save()

        let service = CaptureQueueService(container: container)
        service.recoverOrphanedJobs()

        let fetched = try ctx.fetch(FetchDescriptor<CaptureJob>())
        let statuses = Set(fetched.map(\.status))
        XCTAssertEqual(statuses, [.committed, .failed],
                       "Recovery only touches .processing jobs")
    }
}
