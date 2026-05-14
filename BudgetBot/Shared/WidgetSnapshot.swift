import Foundation

/// The slim, Codable view of "right now" that the BudgetBot Home Screen
/// widget renders from. Lives in `Shared/` so both the main app *and*
/// the widget extension target compile it.
///
/// Design choice: rather than have the widget read SwiftData directly
/// (which would require moving the SQLite store into the App Group
/// container — a migration we deliberately reverted in an earlier
/// commit), the main app **writes** this struct to a JSON file in the
/// App Group container after every save. The widget **reads** it. Small
/// blob, easy to evolve, no schema migration risk.
public struct WidgetSnapshot: Codable, Equatable {
    public let baseCurrency: String
    /// Total expense in `baseCurrency`, month-to-date.
    public let monthSpent: Decimal
    /// User's configured monthly budget, or `nil` if not set.
    public let monthBudget: Decimal?
    /// Daily-average expense over the current calendar month so far.
    public let dailyAverage: Decimal
    /// Top expense category name + emoji, or `nil` if no spend yet.
    public let topCategoryName: String?
    public let topCategoryEmoji: String?
    /// When the snapshot was last written. Widgets surface staleness in
    /// the rare case the main app hasn't run in days.
    public let updatedAt: Date

    public init(
        baseCurrency: String,
        monthSpent: Decimal,
        monthBudget: Decimal?,
        dailyAverage: Decimal,
        topCategoryName: String?,
        topCategoryEmoji: String?,
        updatedAt: Date = .now
    ) {
        self.baseCurrency = baseCurrency
        self.monthSpent = monthSpent
        self.monthBudget = monthBudget
        self.dailyAverage = dailyAverage
        self.topCategoryName = topCategoryName
        self.topCategoryEmoji = topCategoryEmoji
        self.updatedAt = updatedAt
    }

    /// A safe, useful empty state used by both the writer (no data yet)
    /// and the widget reader (no snapshot file yet).
    public static let empty = WidgetSnapshot(
        baseCurrency: "EUR",
        monthSpent: 0,
        monthBudget: nil,
        dailyAverage: 0,
        topCategoryName: nil,
        topCategoryEmoji: nil
    )
}

/// Where the snapshot lives in the shared container, plus the read/write
/// helpers. Pure file IO — no AppKit/SwiftUI dependency so the widget
/// extension can import this exact file.
public enum WidgetSnapshotStore {
    public static let filename = "widget-snapshot.json"

    public static func url() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedConfig.appGroupID)?
            .appendingPathComponent(filename)
    }

    @discardableResult
    public static func write(_ snapshot: WidgetSnapshot) -> Bool {
        guard let url = url(),
              let data = try? JSONEncoder.iso8601().encode(snapshot)
        else { return false }
        do {
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    public static func read() -> WidgetSnapshot {
        guard let url = url(),
              let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder.iso8601().decode(WidgetSnapshot.self, from: data)
        else { return .empty }
        return snap
    }
}

// MARK: - Helpers

private extension JSONEncoder {
    static func iso8601() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

private extension JSONDecoder {
    static func iso8601() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
