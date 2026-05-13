import Foundation
import SwiftData

/// Single source of truth for the SwiftData stack. Versioned so we can add
/// migrations without losing user data, and exposes an in-memory variant
/// for tests + previews.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] = [
        UserProfile.self,
        Account.self,
        TxCategory.self,
        Transaction.self,
        Split.self,
        Attachment.self,
        AIRecommendation.self,
        FXRateSnapshot.self,
        RecurringRule.self
    ]
}

enum BudgetBotMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] = [SchemaV1.self]
    static var stages: [MigrationStage] = []   // grow as we add SchemaV2 etc.
}

enum PersistenceController {
    private static let storeFilename = "BudgetBotStore.store"

    /// Default on-disk store. If the store on disk doesn't match the current
    /// schema (we're pre-1.0, models are still evolving), wipe it and retry
    /// rather than crashing the user. **Drop this fallback after launch** —
    /// at that point a schema change must come with a real `MigrationStage`.
    @MainActor
    static let live: ModelContainer = {
        do {
            return try buildContainer(inMemory: false)
        } catch {
            print("⚠️ ModelContainer failed to load (pre-1.0 schema drift): \(error). Wiping store and retrying.")
            wipeOnDiskStore()
            do {
                return try buildContainer(inMemory: false)
            } catch {
                fatalError("Could not rebuild ModelContainer after wipe: \(error)")
            }
        }
    }()

    /// Fresh in-memory container — use in tests & previews.
    static func makeInMemory() throws -> ModelContainer {
        try buildContainer(inMemory: true, name: "BudgetBotMemory")
    }

    // MARK: - Internals

    private static func buildContainer(inMemory: Bool, name: String = "BudgetBotStore") throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(
            name,
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            allowsSave: true
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: BudgetBotMigrationPlan.self,
            configurations: [config]
        )
    }

    /// Removes the on-disk SQLite store and its WAL/SHM siblings. Used by the
    /// pre-1.0 schema-drift recovery in `live` and by UI-test reset.
    static func wipeOnDiskStore() {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }
        for suffix in ["", "-shm", "-wal"] {
            let url = appSupport.appendingPathComponent("\(storeFilename)\(suffix)")
            try? fm.removeItem(at: url)
        }
    }
}
