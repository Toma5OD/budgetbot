import XCTest
@testable import BudgetBot

final class WidgetSnapshotTests: XCTestCase {

    func test_emptySnapshot_hasSafeDefaults() {
        let s = WidgetSnapshot.empty
        XCTAssertEqual(s.monthSpent, 0)
        XCTAssertNil(s.monthBudget)
        XCTAssertNil(s.topCategoryName)
        XCTAssertEqual(s.baseCurrency, "EUR")
    }

    func test_snapshot_roundTripsThroughJSON() throws {
        let original = WidgetSnapshot(
            baseCurrency: "USD",
            monthSpent: 1_234.56,
            monthBudget: 2_500,
            dailyAverage: 41.15,
            topCategoryName: "Groceries",
            topCategoryEmoji: "🛒",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601

        let data = try enc.encode(original)
        let decoded = try dec.decode(WidgetSnapshot.self, from: data)
        XCTAssertEqual(decoded, original,
                       "Snapshot must survive a JSON round trip — widget reads what main app writes")
    }

    func test_writeThenRead_returnsTheWrittenSnapshot() throws {
        // Skip if the test process can't see the App Group container
        // (CI/simulator without the entitlement registered — perfectly
        // fine, just not a fast-feedback path).
        guard WidgetSnapshotStore.url() != nil else {
            throw XCTSkip("App Group container unavailable in this test runtime")
        }
        let s = WidgetSnapshot(
            baseCurrency: "EUR",
            monthSpent: 99,
            monthBudget: 100,
            dailyAverage: 3.3,
            topCategoryName: "Coffee",
            topCategoryEmoji: "☕️"
        )
        XCTAssertTrue(WidgetSnapshotStore.write(s))
        let back = WidgetSnapshotStore.read()
        XCTAssertEqual(back.baseCurrency, "EUR")
        XCTAssertEqual(back.monthSpent, 99)
        XCTAssertEqual(back.monthBudget, 100)
    }
}
