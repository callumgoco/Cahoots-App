import Foundation

@MainActor
protocol AppRepository {
    var mode: AppMode { get }
    func load() async throws -> DemoSnapshot
    func save(_ snapshot: DemoSnapshot) async throws
    func reset() async throws -> DemoSnapshot
    func syncSubmission(_ submission: Submission, challengeTimezone: String) async -> SubmissionSyncResult
    func perform(_ command: RepositoryCommand) async throws -> DemoSnapshot?
    func requestClipUploadURL(groupID: UUID, challengeID: UUID, requirementDateToken: String, clipID: UUID) async throws -> ClipUploadTicket
    func uploadClip(ticket: ClipUploadTicket, fileURL: URL) async throws
    func requestClipDownloadURL(clipID: UUID) async throws -> ClipDownloadTicket
    func clearLocalOfflineState() async throws
}

extension AppRepository {
    func clearLocalOfflineState() async throws {}
}

struct ClipUploadTicket: Sendable {
    var storagePath: String
    var uploadURL: URL
    var token: String?
    var clipID: UUID
}

struct ClipDownloadTicket: Sendable {
    var downloadURL: URL
    var storagePath: String
    var clipID: UUID
    var expiresIn: Int
}

struct SubmissionReceipt: Codable, Hashable, Sendable {
    var submissionID: UUID
    var acceptedAt: Date
}

enum SubmissionSyncResult: Hashable, Sendable {
    /// `uploadedClips` carries any clip rows that already have a remote path so retries skip re-upload.
    case accepted(SubmissionReceipt, uploadedClips: [WorkoutClip] = [])
    case rejected(String)
    case retryable(String, retryAfter: TimeInterval?, uploadedClips: [WorkoutClip] = [])
    case authenticationRequired(uploadedClips: [WorkoutClip] = [])
}

protocol EntitlementService: Sendable {
    func currentEntitlement() async -> Entitlement
}

struct FreeEntitlementService: EntitlementService {
    func currentEntitlement() async -> Entitlement { .free }
}

enum RepositoryError: LocalizedError {
    case invalidConfiguration
    case authenticationRequired
    case emailConfirmationRequired
    case server(String)
    case corruptedLocalData

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Live backend configuration is incomplete."
        case .authenticationRequired: "Your session has expired. Please sign in again."
        case .emailConfirmationRequired: "Confirm your email before signing in."
        case .server(let message): Self.readable(message)
        case .corruptedLocalData: "Cahoots could not read the saved local data. The original data has been preserved so you can retry or explicitly reset it."
        }
    }

    /// Postgres raises the rules it enforces as bare codes, which are not meant to be read.
    static func readable(_ message: String) -> String {
        switch message {
        case "transfer_ownership_required": "You still own a group with other members. Make someone else the owner first."
        case "not_a_member": "You are no longer a member of that group."
        case "not_allowed": "You do not have permission to do that."
        case "not_authenticated": "Your session has expired. Please sign in again."
        case "rate_limited": "Too many attempts. Wait a moment and try again."
        default: message
        }
    }
}
