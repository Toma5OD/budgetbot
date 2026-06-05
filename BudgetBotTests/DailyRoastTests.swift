import XCTest
@testable import BudgetBot

final class DailyRoastTests: XCTestCase {

    /// Fixed reference date — keeps day-of-year picks deterministic.
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func tx(_ payee: String,
                    _ amount: Decimal,
                    daysAgo: Int = 0,
                    category: String? = nil) -> DailyRoast.TxSnapshot {
        let cal = Calendar.current
        let date = cal.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        return .init(payee: payee, amount: amount, date: date, categoryName: category)
    }

    private func empty() -> DailyRoast.Input {
        DailyRoast.Input(
            now: now,
            recentTransactions: [],
            activeGoals: [],
            subscriptionCount: 0
        )
    }

    // MARK: - Fallback

    func test_emptyInput_returnsFallbackNeutralLine() {
        let lines = DailyRoast.generate(input: empty())
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines.first?.tone, .neutral)
    }

    // MARK: - Rules

    func test_coffeeRule_firesAtThreeOrMore() {
        let input = DailyRoast.Input(
            now: now,
            recentTransactions: [
                tx("Starbucks", -4.50, daysAgo: 1),
                tx("Costa",     -4.50, daysAgo: 2),
                tx("Insomnia",  -4.50, daysAgo: 3)
            ],
            activeGoals: [],
            subscriptionCount: 0
        )
        let lines = DailyRoast.generate(input: input)
        XCTAssertTrue(lines.contains { $0.tone == .roast })
    }

    func test_takeawayRule_firesOnRecentFastFood() {
        let input = DailyRoast.Input(
            now: now,
            recentTransactions: [tx("Domino's Pizza", -22, daysAgo: 0)],
            activeGoals: [],
            subscriptionCount: 0
        )
        let lines = DailyRoast.generate(input: input)
        XCTAssertTrue(lines.contains { $0.tone == .roast })
    }

    func test_bigSpendRule_namesTheMerchant() {
        let input = DailyRoast.Input(
            now: now,
            recentTransactions: [
                tx("Currys", -899, daysAgo: 2, category: "Electronics")
            ],
            activeGoals: [],
            subscriptionCount: 0
        )
        let lines = DailyRoast.generate(input: input)
        XCTAssertTrue(lines.contains { $0.text.contains("Currys") })
    }

    func test_bigSpendRule_ignoresRent() {
        let input = DailyRoast.Input(
            now: now,
            recentTransactions: [
                tx("Murphy Property Mgmt", -1_950, daysAgo: 1, category: "Rent")
            ],
            activeGoals: [],
            subscriptionCount: 0
        )
        let lines = DailyRoast.generate(input: input)
        XCTAssertFalse(lines.contains { $0.text.contains("Murphy Property") })
    }

    func test_subscriptionRule_firesAtFiveOrMore() {
        let input = DailyRoast.Input(
            now: now,
            recentTransactions: [],
            activeGoals: [],
            subscriptionCount: 6
        )
        let lines = DailyRoast.generate(input: input)
        XCTAssertTrue(lines.contains { $0.tone == .roast })
    }

    func test_savingsRule_praisesOnTrackGoal() {
        let input = DailyRoast.Input(
            now: now,
            recentTransactions: [],
            activeGoals: [.init(isHit: false, pace: .onTrack, completedAt: nil)],
            subscriptionCount: 0
        )
        let lines = DailyRoast.generate(input: input)
        XCTAssertTrue(lines.contains { $0.tone == .praise })
    }

    func test_goalHitToday_takesTopPriority() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let input = DailyRoast.Input(
            now: now,
            recentTransactions: [
                tx("Domino's Pizza", -22, daysAgo: 0),
                tx("Currys",         -899, daysAgo: 2)
            ],
            activeGoals: [.init(isHit: true, pace: .ahead, completedAt: today)],
            subscriptionCount: 8
        )
        let lines = DailyRoast.generate(input: input)
        XCTAssertEqual(lines.first?.tone, .praise,
                       "Goal-hit-today must lead the day's roast.")
    }

    // MARK: - Invariants

    func test_atMostThreeLines() {
        let input = DailyRoast.Input(
            now: now,
            recentTransactions: [
                tx("Starbucks",      -4,   daysAgo: 1),
                tx("Costa",          -4,   daysAgo: 2),
                tx("Insomnia",       -4,   daysAgo: 3),
                tx("Domino's Pizza", -20,  daysAgo: 0),
                tx("Currys",         -800, daysAgo: 2)
            ],
            activeGoals: [.init(isHit: false, pace: .ahead, completedAt: nil)],
            subscriptionCount: 8
        )
        let lines = DailyRoast.generate(input: input)
        XCTAssertLessThanOrEqual(lines.count, 3)
    }

    func test_sameDataSameDayProducesSameLines() {
        let input = DailyRoast.Input(
            now: now,
            recentTransactions: [tx("Domino's Pizza", -20, daysAgo: 0)],
            activeGoals: [],
            subscriptionCount: 0
        )
        XCTAssertEqual(DailyRoast.generate(input: input),
                       DailyRoast.generate(input: input))
    }
}
