import XCTest
@testable import BudgetBot

final class RewardCatalogTests: XCTestCase {

    func test_catalogIsNonEmpty() {
        XCTAssertFalse(RewardCatalog.all.isEmpty)
    }

    func test_idsAreUnique() {
        let ids = RewardCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func test_getResolvesByID() {
        for pkg in RewardCatalog.all {
            XCTAssertEqual(RewardCatalog.get(id: pkg.id)?.id, pkg.id)
        }
        XCTAssertNil(RewardCatalog.get(id: "nonexistent"))
    }

    func test_tieredCoverage() {
        // The picker needs something at every goal size — small,
        // medium, large. If a tier is empty, big-saver users see
        // nothing aspirational, and small-saver users see only
        // packages priced above their goal.
        let tiers = Set(RewardCatalog.all.map(\.tier))
        XCTAssertEqual(tiers, Set([.small, .medium, .large]))
    }

    func test_tierForGoalAmount() {
        XCTAssertEqual(RewardCatalog.tier(forGoalAmount: 50),     .small)
        XCTAssertEqual(RewardCatalog.tier(forGoalAmount: 499),    .small)
        XCTAssertEqual(RewardCatalog.tier(forGoalAmount: 500),    .medium)
        XCTAssertEqual(RewardCatalog.tier(forGoalAmount: 5_000),  .medium)
        XCTAssertEqual(RewardCatalog.tier(forGoalAmount: 9_999),  .medium)
        XCTAssertEqual(RewardCatalog.tier(forGoalAmount: 10_000), .large)
        XCTAssertEqual(RewardCatalog.tier(forGoalAmount: 50_000), .large)
    }
}
