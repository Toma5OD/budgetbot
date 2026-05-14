import XCTest
import SwiftData
@testable import BudgetBot

@MainActor
final class SavingsGoalTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        try PersistenceController.makeInMemory()
    }

    func test_progress_isCurrentOverTarget_clampedAtOne() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let g = SavingsGoal(name: "Japan", targetAmount: 1000, currency: "EUR")
        ctx.insert(g)
        XCTAssertEqual(g.progress, 0)

        ctx.insert(GoalContribution(amount: 250, goal: g))
        XCTAssertEqual(g.progress, 0.25, accuracy: 0.001)

        ctx.insert(GoalContribution(amount: 800, goal: g))
        XCTAssertEqual(g.progress, 1.0, "Overshoot clamped at 1")
        XCTAssertTrue(g.isHit)
        XCTAssertEqual(g.currentAmount, 1050)
        XCTAssertEqual(g.remaining, 0, "Remaining can't go negative")
    }

    func test_daysRemaining_isPositiveBeforeDeadline_zeroAfter() {
        let cal = Calendar.current
        let future = cal.date(byAdding: .day, value: 7, to: .now)!
        let past   = cal.date(byAdding: .day, value: -7, to: .now)!

        let g1 = SavingsGoal(name: "Future", targetAmount: 100, deadline: future)
        XCTAssertGreaterThanOrEqual(g1.daysRemaining ?? -1, 6)

        let g2 = SavingsGoal(name: "Past", targetAmount: 100, deadline: past)
        XCTAssertEqual(g2.daysRemaining, 0,
                       "Past deadline clamps to 0, not negative")

        let g3 = SavingsGoal(name: "Open-ended", targetAmount: 100)
        XCTAssertNil(g3.daysRemaining)
    }

    func test_requiredPerDay_isRemainingOverDays() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let cal = Calendar.current
        let in10 = cal.date(byAdding: .day, value: 10, to: .now)!

        let g = SavingsGoal(name: "Bike", targetAmount: 500, deadline: in10)
        ctx.insert(g)
        ctx.insert(GoalContribution(amount: 100, goal: g))

        let perDay = g.requiredPerDay
        XCTAssertNotNil(perDay)
        XCTAssertEqual(perDay!, 40,
                       "(500-100)/10 = 40 per day required")
    }

    func test_requiredPerDay_isNilWhenAlreadyHit() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let cal = Calendar.current
        let future = cal.date(byAdding: .day, value: 30, to: .now)!

        let g = SavingsGoal(name: "Done", targetAmount: 100, deadline: future)
        ctx.insert(g)
        ctx.insert(GoalContribution(amount: 120, goal: g))
        XCTAssertTrue(g.isHit)
        XCTAssertNil(g.requiredPerDay,
                     "Already hit → no per-day required")
    }

    func test_pace_noDeadline_isNoDeadline() {
        let g = SavingsGoal(name: "Open", targetAmount: 1000)
        XCTAssertEqual(g.pace, .noDeadline)
    }

    func test_deletingGoal_cascadesToContributions() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let g = SavingsGoal(name: "Trip", targetAmount: 1000)
        ctx.insert(g)
        ctx.insert(GoalContribution(amount: 50, goal: g))
        ctx.insert(GoalContribution(amount: 30, goal: g))
        try ctx.save()

        XCTAssertEqual(try ctx.fetch(FetchDescriptor<GoalContribution>()).count, 2)
        ctx.delete(g)
        try ctx.save()
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<GoalContribution>()).count, 0,
                       "Deleting a goal should cascade-delete its contributions")
    }
}
