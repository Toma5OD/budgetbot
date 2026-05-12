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
        Attachment.self,
        AIRecommendation.self,
        FXRateSnapshot.self
    ]
}

enum BudgetBotMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] = [SchemaV1.self]
    static var stages: [MigrationStage] = []   // grow as we add SchemaV2 etc.
}

enum PersistenceController {
    /// Default on-disk store living under the app's Application Support directory.
    @MainActor
    static let live: ModelContainer = {
        do {
            let schema = Schema(versionedSchema: SchemaV1.self)
            let config = ModelConfiguration(
                "BudgetBotStore",
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true
            )
            return try ModelContainer(
                for: schema,
                migrationPlan: BudgetBotMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            fatalError("Failed to build live ModelContainer: \(error)")
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
}
