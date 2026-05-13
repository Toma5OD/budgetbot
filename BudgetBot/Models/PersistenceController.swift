import Foundation
import SwiftData

/// Single source of truth for the SwiftData stack.
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
    static var stages: [MigrationStage] = []
}

enum PersistenceController {
    private static let storeFilename = "BudgetBotStore.store"

    /// Where the SwiftData store actually lives. We pin it explicitly to the
    /// app's own `Library/Application Support` rather than letting SwiftData
    /// route into the App Group container (which it does by default once the
    /// `com.apple.security.application-groups` entitlement is present).
    ///
    /// The App Group is for the Share Extension's pending-capture queue,
    /// **not** for the main database — putting the DB there would expose every
    /// transaction to any extension running in the group, and it's why the
    /// store kept getting reused across schema rewrites during dev.
    private static var storeURL: URL? {
        let fm = FileManager.default
        guard let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(storeFilename)
    }

    /// Default on-disk store. If the store on disk doesn't match the current
    /// schema (we're pre-1.0, models are still evolving), wipe and retry
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
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(
            "BudgetBotMemory",
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Internals

    private static func buildContainer(inMemory: Bool) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config: ModelConfiguration
        if inMemory {
            // No CloudKit when in-memory — tests stay isolated and offline.
            config = ModelConfiguration(
                "BudgetBotStore",
                schema: schema,
                isStoredInMemoryOnly: true,
                allowsSave: true,
                cloudKitDatabase: .none
            )
        } else if let url = storeURL {
            // Pin the URL so SwiftData can't reroute into the App Group
            // container. `.automatic` enables CloudKit private-database sync
            // when the iCloud entitlement is registered with the team AND the
            // user is signed into iCloud on the device. Falls back to
            // local-only otherwise — Sim users without iCloud just see a
            // single-device app.
            config = ModelConfiguration(
                "BudgetBotStore",
                schema: schema,
                url: url,
                allowsSave: true,
                cloudKitDatabase: .automatic
            )
        } else {
            config = ModelConfiguration(
                "BudgetBotStore",
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true,
                cloudKitDatabase: .automatic
            )
        }
        return try ModelContainer(
            for: schema,
            migrationPlan: BudgetBotMigrationPlan.self,
            configurations: [config]
        )
    }

    /// Removes the on-disk SQLite store + WAL/SHM siblings from both the app's
    /// own Application Support directory AND the App Group container (where
    /// older builds accidentally wrote it). Used by the pre-1.0 schema-drift
    /// recovery in `live` and by UI-test reset.
    static func wipeOnDiskStore() {
        let fm = FileManager.default
        var dirsToClean: [URL] = []

        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            dirsToClean.append(appSupport)
        }
        // The App Group's Application Support — where pre-fix builds put the store.
        if let appGroup = fm.containerURL(forSecurityApplicationGroupIdentifier: SharedConfig.appGroupID) {
            let appGroupAppSupport = appGroup.appendingPathComponent("Library/Application Support")
            dirsToClean.append(appGroupAppSupport)
        }

        for dir in dirsToClean {
            for suffix in ["", "-shm", "-wal"] {
                let url = dir.appendingPathComponent("\(storeFilename)\(suffix)")
                try? fm.removeItem(at: url)
            }
        }
    }
}
