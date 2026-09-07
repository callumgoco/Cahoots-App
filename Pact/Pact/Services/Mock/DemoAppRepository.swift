import Foundation
import SwiftData

@MainActor
final class DemoAppRepository: AppRepository {
    let mode: AppMode = .demo
    private let context: ModelContext
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(context: ModelContext) {
        self.context = context
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() async throws -> DemoSnapshot {
        let descriptor = FetchDescriptor<AppSnapshotEntity>(predicate: #Predicate { $0.key == "primary" })
        if let record = try context.fetch(descriptor).first {
            if let envelope = try? decoder.decode(SnapshotEnvelope.self, from: record.payload) {
                return SnapshotMigrator.migrate(envelope.snapshot)
            }
            if let legacy = try? decoder.decode(DemoSnapshot.self, from: record.payload) {
                let migrated = SnapshotMigrator.migrate(legacy)
                try await save(migrated)
                return migrated
            }
            throw RepositoryError.corruptedLocalData
        }
        let seed = SnapshotMigrator.migrate(DemoSeed.make())
        try await save(seed)
        return seed
    }

    func save(_ snapshot: DemoSnapshot) async throws {
        let payload = try encoder.encode(SnapshotEnvelope(version: 3, snapshot: SnapshotMigrator.migrate(snapshot)))
        let descriptor = FetchDescriptor<AppSnapshotEntity>(predicate: #Predicate { $0.key == "primary" })
        if let record = try context.fetch(descriptor).first {
            let backupDescriptor = FetchDescriptor<AppSnapshotEntity>(predicate: #Predicate { $0.key == "last-known-good" })
            if let backup = try context.fetch(backupDescriptor).first {
                backup.payload = record.payload
                backup.updatedAt = record.updatedAt
            } else {
                context.insert(AppSnapshotEntity(key: "last-known-good", payload: record.payload, updatedAt: record.updatedAt))
            }
            record.payload = payload
            record.updatedAt = .now
        } else {
            context.insert(AppSnapshotEntity(payload: payload))
        }
        try context.save()
    }

    func reset() async throws -> DemoSnapshot {
        let records = try context.fetch(FetchDescriptor<AppSnapshotEntity>())
        records.forEach(context.delete)
        let seed = SnapshotMigrator.migrate(DemoSeed.make())
        try await save(seed)
        return seed
    }

    func syncSubmission(_ submission: Submission) async -> SubmissionSyncResult {
        .accepted(.init(submissionID: submission.id, acceptedAt: .now))
    }

    func perform(_ command: RepositoryCommand) async throws -> DemoSnapshot? {
        let current = try await load()
        let (updated, _) = try SnapshotCommandApplier.apply(command, to: current, now: .now)
        try await save(updated)
        return updated
    }

    func requestClipUploadURL(groupID: UUID, challengeID: UUID, requirementDate: Date, clipID: UUID) async throws -> ClipUploadTicket {
        ClipUploadTicket(
            storagePath: "demo/\(groupID.uuidString)/\(clipID.uuidString).mov",
            uploadURL: URL(fileURLWithPath: "/dev/null"),
            token: nil,
            clipID: clipID
        )
    }

    func uploadClip(ticket: ClipUploadTicket, fileURL: URL) async throws {
        // Demo mode keeps clips local only.
    }
}

private struct SnapshotEnvelope: Codable {
    var version: Int
    var snapshot: DemoSnapshot
}
