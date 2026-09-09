import Foundation
import SwiftData

/// Persists a versioned offline overlay (pending check-ins) via SwiftData.
@MainActor
final class LocalSnapshotStore {
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

    func loadFullSnapshot() throws -> DemoSnapshot? {
        let descriptor = FetchDescriptor<AppSnapshotEntity>(predicate: #Predicate { $0.key == "primary" })
        guard let record = try context.fetch(descriptor).first else { return nil }
        if let envelope = try? decoder.decode(SnapshotEnvelope.self, from: record.payload) {
            return SnapshotMigrator.migrate(envelope.snapshot)
        }
        if let legacy = try? decoder.decode(DemoSnapshot.self, from: record.payload) {
            return SnapshotMigrator.migrate(legacy)
        }
        throw RepositoryError.corruptedLocalData
    }

    func saveFullSnapshot(_ snapshot: DemoSnapshot) throws {
        let migrated = SnapshotMigrator.migrate(snapshot)
        let payload = try encoder.encode(SnapshotEnvelope(version: 3, snapshot: migrated))
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
            context.insert(AppSnapshotEntity(key: "primary", payload: payload))
        }
        try context.save()
    }

    func clearAll() throws {
        let records = try context.fetch(FetchDescriptor<AppSnapshotEntity>())
        records.forEach(context.delete)
        try context.save()
    }

    // MARK: Live overlay (pending check-ins only)

    func loadLiveOverlay() throws -> LiveOfflineOverlay {
        let descriptor = FetchDescriptor<AppSnapshotEntity>(predicate: #Predicate { $0.key == "live-offline-overlay" })
        guard let record = try context.fetch(descriptor).first else {
            return LiveOfflineOverlay(pendingOperations: [], submissions: [])
        }
        return (try? decoder.decode(LiveOfflineOverlay.self, from: record.payload))
            ?? LiveOfflineOverlay(pendingOperations: [], submissions: [])
    }

    func saveLiveOverlay(from snapshot: DemoSnapshot) throws {
        let unsyncedStates: Set<SyncState> = [.waiting, .failed]
        let pendingIDs = Set(snapshot.pendingOperations.map(\.clientGeneratedID))
        let submissions = snapshot.submissions.filter {
            unsyncedStates.contains($0.syncState) || pendingIDs.contains($0.clientGeneratedID)
        }
        let overlay = LiveOfflineOverlay(
            pendingOperations: snapshot.pendingOperations,
            submissions: submissions
        )
        let payload = try encoder.encode(overlay)
        let descriptor = FetchDescriptor<AppSnapshotEntity>(predicate: #Predicate { $0.key == "live-offline-overlay" })
        if let record = try context.fetch(descriptor).first {
            record.payload = payload
            record.updatedAt = .now
        } else {
            context.insert(AppSnapshotEntity(key: "live-offline-overlay", payload: payload))
        }
        try context.save()
    }

    func clearLiveOverlay() throws {
        let descriptor = FetchDescriptor<AppSnapshotEntity>(predicate: #Predicate { $0.key == "live-offline-overlay" })
        for record in try context.fetch(descriptor) {
            context.delete(record)
        }
        try context.save()
    }

    static func merge(server: DemoSnapshot, overlay: LiveOfflineOverlay) -> DemoSnapshot {
        var merged = server
        let serverPendingIDs = Set(server.pendingOperations.map(\.clientGeneratedID))
        let serverSubmissionIDs = Set(server.submissions.map(\.clientGeneratedID))

        let localPending = overlay.pendingOperations.filter { !serverPendingIDs.contains($0.clientGeneratedID) }
        merged.pendingOperations = server.pendingOperations + localPending

        let localSubmissions = overlay.submissions.filter { !serverSubmissionIDs.contains($0.clientGeneratedID) }
        merged.submissions = server.submissions + localSubmissions
        return merged
    }
}

struct SnapshotEnvelope: Codable {
    var version: Int
    var snapshot: DemoSnapshot
}

struct LiveOfflineOverlay: Codable, Sendable {
    var pendingOperations: [PendingSyncOperation]
    var submissions: [Submission]
}
