import Foundation
import SwiftData

@MainActor
final class DemoAppRepository: AppRepository {
    let mode: AppMode = .demo
    private let store: LocalSnapshotStore

    init(context: ModelContext) {
        store = LocalSnapshotStore(context: context)
    }

    func load() async throws -> DemoSnapshot {
        if let existing = try store.loadFullSnapshot() {
            return existing
        }
        let seed = makeSeed()
        try await save(seed)
        return seed
    }

    func save(_ snapshot: DemoSnapshot) async throws {
        try store.saveFullSnapshot(snapshot)
    }

    func reset() async throws -> DemoSnapshot {
        try store.clearAll()
        let seed = makeSeed()
        try await save(seed)
        return seed
    }

    private func makeSeed() -> DemoSnapshot {
        if ProcessInfo.processInfo.arguments.contains("-marketingSeed") {
            return SnapshotMigrator.migrate(MarketingSeed.make())
        }
        return SnapshotMigrator.migrate(DemoSeed.make())
    }

    func syncSubmission(_ submission: Submission, challengeTimezone: String) async -> SubmissionSyncResult {
        .accepted(.init(submissionID: submission.id, acceptedAt: .now))
    }

    func perform(_ command: RepositoryCommand) async throws -> DemoSnapshot? {
        let current = try await load()
        let (updated, _) = try SnapshotCommandApplier.apply(command, to: current, now: .now)
        try await save(updated)
        return updated
    }

    func requestClipUploadURL(groupID: UUID, challengeID: UUID, requirementDateToken: String, clipID: UUID) async throws -> ClipUploadTicket {
        ClipUploadTicket(
            storagePath: "demo/\(groupID.uuidString)/\(requirementDateToken)/\(clipID.uuidString).mov",
            uploadURL: URL(fileURLWithPath: "/dev/null"),
            token: nil,
            clipID: clipID
        )
    }

    func uploadClip(ticket: ClipUploadTicket, fileURL: URL) async throws {
        // Demo mode keeps clips local only.
    }

    func requestClipDownloadURL(clipID: UUID) async throws -> ClipDownloadTicket {
        let snapshot = try await load()
        let clip = snapshot.submissions.flatMap(\.clips).first { $0.id == clipID }
        guard let clip, let filename = clip.localFilename else {
            throw RepositoryError.server("Clip is not available.")
        }
        let fileURL = WorkoutClipStore.fileURL(for: filename)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw RepositoryError.server("Clip is not available.")
        }
        return ClipDownloadTicket(
            downloadURL: fileURL,
            storagePath: clip.remotePath ?? filename,
            clipID: clipID,
            expiresIn: 3_600
        )
    }
}
