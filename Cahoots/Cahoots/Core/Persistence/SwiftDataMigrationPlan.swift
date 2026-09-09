import SwiftData

enum CahootsSwiftDataSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            AppSnapshotEntity.self,
            CachedUserEntity.self,
            CachedGroupEntity.self,
            CachedChallengeEntity.self,
            CachedSubmissionEntity.self,
            CachedScoreEventEntity.self
        ]
    }
}

enum CahootsSwiftDataMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [CahootsSwiftDataSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
