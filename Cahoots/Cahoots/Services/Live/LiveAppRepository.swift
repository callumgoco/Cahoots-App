import Foundation
import SwiftData

@MainActor
final class LiveAppRepository: AppRepository {
    let mode: AppMode = .live
    private let client: SupabaseClient
    private let localStore: LocalSnapshotStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(configuration: SupabaseConfiguration, keychain: KeychainStore, modelContext: ModelContext) {
        client = SupabaseClient(configuration: configuration, keychain: keychain)
        localStore = LocalSnapshotStore(context: modelContext)
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() async throws -> DemoSnapshot {
        let data = try await client.request(path: "/functions/v1/app-snapshot")
        let server = try decoder.decode(DemoSnapshot.self, from: data)
        let overlay = (try? localStore.loadLiveOverlay()) ?? LiveOfflineOverlay(pendingOperations: [], submissions: [])
        return LocalSnapshotStore.merge(server: server, overlay: overlay)
    }

    func save(_ snapshot: DemoSnapshot) async throws {
        try localStore.saveLiveOverlay(from: snapshot)
    }

    func reset() async throws -> DemoSnapshot {
        try? localStore.clearLiveOverlay()
        return try await load()
    }

    func clearLocalOfflineState() async throws {
        try localStore.clearLiveOverlay()
    }

    func syncSubmission(_ submission: Submission) async -> SubmissionSyncResult {
        do {
            var payload = submission
            var uploadedClips: [WorkoutClip] = []
            for clip in submission.clips {
                var copy = clip
                if copy.remotePath == nil, let filename = copy.localFilename {
                    let ticket = try await requestClipUploadURL(
                        groupID: UUID(), // server derives group from challenge
                        challengeID: submission.challengeID,
                        requirementDate: submission.requirementDate,
                        clipID: clip.id
                    )
                    try await uploadClip(ticket: ticket, fileURL: WorkoutClipStore.fileURL(for: filename))
                    copy.remotePath = ticket.storagePath
                }
                uploadedClips.append(copy)
            }
            payload.clips = uploadedClips
            let body = try encoder.encode(payload)
            _ = try await client.request(path: "/functions/v1/submit-workout", method: "POST", body: body)
            return .accepted(.init(submissionID: submission.id, acceptedAt: .now))
        } catch RepositoryError.authenticationRequired {
            return .authenticationRequired
        } catch let error as RepositoryError {
            if case .server(let message) = error,
               message.lowercased().contains("reject") || message.lowercased().contains("invalid_submission") {
                return .rejected(message)
            }
            return .retryable(error.localizedDescription, retryAfter: nil)
        } catch {
            return .retryable(error.localizedDescription, retryAfter: nil)
        }
    }

    func perform(_ command: RepositoryCommand) async throws -> DemoSnapshot? {
        switch command {
        case .createGroup(let name, let emoji, let memberLimit):
            _ = try await client.rpc("create_private_group", parameters: [
                "group_name": name,
                "group_emoji": emoji,
                "requested_limit": memberLimit
            ])

        case .joinGroup(let code):
            _ = try await client.rpc("redeem_group_invite", parameters: [
                "invite_code": code
            ])

        case .createProposal(let groupID, let draft):
            _ = try await client.rpc("create_and_open_proposal", parameters: proposalParams(groupID: groupID, draft: draft, startKey: "proposed_start_date_input"))

        case .startChallenge(let groupID, let draft):
            _ = try await client.rpc("start_round_now", parameters: proposalParams(groupID: groupID, draft: draft, startKey: "start_date_input"))

        case .castVote(let proposalID, let choice):
            _ = try await client.rpc("cast_vote", parameters: [
                "proposal_id_input": proposalID.uuidString,
                "selected_choice": choice.rawValue
            ])

        case .useRecoveryDay(let challengeID):
            _ = try await client.rpc("use_recovery_day", parameters: [
                "challenge_id_input": challengeID.uuidString
            ])

        case .updateProfile(let displayName, let appearance, let showsExactTotals):
            var params: [String: Any] = [:]
            if let displayName { params["display_name_input"] = displayName }
            if let appearance { params["appearance_input"] = appearance.rawValue }
            if let showsExactTotals { params["shows_exact_totals_input"] = showsExactTotals }
            try await client.rpcVoid("update_my_profile", parameters: params)

        case .updateNotificationSettings(let settings):
            let payload: [String: Any] = [
                "quietHoursStart": settings.quietHoursStart,
                "quietHoursEnd": settings.quietHoursEnd,
                "defaultReminderMinutes": settings.defaultReminderMinutes,
                "primerDismissed": settings.primerDismissed,
                "groups": settings.groups.map { group -> [String: Any] in
                    var row: [String: Any] = [
                        "groupID": group.groupID.uuidString,
                        "personalRemindersEnabled": group.personalRemindersEnabled,
                        "friendActivityMode": group.friendActivityMode.rawValue,
                        "challengeUpdatesEnabled": group.challengeUpdatesEnabled
                    ]
                    if let reminder = group.reminderMinutes { row["reminderMinutes"] = reminder }
                    return row
                }
            ]
            try await client.rpcVoid("upsert_notification_settings", parameters: [
                "settings_input": payload
            ])

        case .updateGroup(let id, let name, let emoji, let memberLimit):
            try await client.rpcVoid("update_group_settings", parameters: [
                "group_id_input": id.uuidString,
                "name_input": name,
                "emoji_input": emoji,
                "member_limit_input": memberLimit
            ])

        case .setRole(let groupID, let userID, let role):
            try await client.rpcVoid("set_member_role", parameters: [
                "group_id_input": groupID.uuidString,
                "user_id_input": userID.uuidString,
                "role_input": role.rawValue
            ])

        case .transferOwnership(let groupID, let newOwnerID):
            try await client.rpcVoid("transfer_group_ownership", parameters: [
                "group_id_input": groupID.uuidString,
                "new_owner_id": newOwnerID.uuidString
            ])

        case .removeMember(let groupID, let userID):
            try await client.rpcVoid("remove_group_member", parameters: [
                "group_id_input": groupID.uuidString,
                "user_id_input": userID.uuidString
            ])

        case .leaveGroup(let groupID):
            try await client.rpcVoid("leave_group", parameters: [
                "group_id_input": groupID.uuidString
            ])

        case .revokeInvites(let groupID):
            try await client.rpcVoid("revoke_group_invites", parameters: [
                "group_id_input": groupID.uuidString
            ])

        case .regenerateInvite(let groupID):
            _ = try await client.rpc("regenerate_group_invite", parameters: [
                "group_id_input": groupID.uuidString
            ])

        case .block(let userID):
            try await client.rpcVoid("block_user", parameters: [
                "blocked_user_id_input": userID.uuidString
            ])

        case .unblock(let userID):
            try await client.rpcVoid("unblock_user", parameters: [
                "blocked_user_id_input": userID.uuidString
            ])

        case .report(let userID, let groupID, let reason):
            _ = try await client.rpc("submit_report", parameters: [
                "reported_user_id_input": userID.uuidString,
                "group_id_input": groupID.uuidString,
                "reason_input": reason
            ])

        case .deleteAccount:
            _ = try await client.request(path: "/functions/v1/delete-account", method: "POST", body: Data("{}".utf8))
            return nil
        }

        return try await load()
    }

    func requestClipUploadURL(groupID: UUID, challengeID: UUID, requirementDate: Date, clipID: UUID) async throws -> ClipUploadTicket {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        let body = try JSONSerialization.data(withJSONObject: [
            "challengeID": challengeID.uuidString,
            "requirementDate": formatter.string(from: requirementDate),
            "clipID": clipID.uuidString
        ])
        let data = try await client.request(path: "/functions/v1/clip-upload-url", method: "POST", body: body)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let storagePath = json["storagePath"] as? String,
              let uploadURLString = json["uploadURL"] as? String,
              let uploadURL = URL(string: uploadURLString) else {
            throw RepositoryError.server("Could not create a clip upload URL.")
        }
        return ClipUploadTicket(
            storagePath: storagePath,
            uploadURL: uploadURL,
            token: json["token"] as? String,
            clipID: clipID
        )
    }

    func uploadClip(ticket: ClipUploadTicket, fileURL: URL) async throws {
        let data = try Data(contentsOf: fileURL)
        try await client.upload(to: ticket.uploadURL, data: data)
    }

    func requestClipDownloadURL(clipID: UUID) async throws -> ClipDownloadTicket {
        let body = try JSONSerialization.data(withJSONObject: [
            "clipID": clipID.uuidString
        ])
        let data = try await client.request(path: "/functions/v1/clip-download-url", method: "POST", body: body)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let downloadURLString = json["downloadURL"] as? String,
              let downloadURL = URL(string: downloadURLString),
              let storagePath = json["storagePath"] as? String else {
            throw RepositoryError.server("Could not create a clip download URL.")
        }
        let expiresIn = json["expiresIn"] as? Int ?? 120
        return ClipDownloadTicket(
            downloadURL: downloadURL,
            storagePath: storagePath,
            clipID: clipID,
            expiresIn: expiresIn
        )
    }

    private func proposalParams(groupID: UUID, draft: ProposalDraft, startKey: String) -> [String: Any] {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        let frequency: String = {
            switch draft.frequencyType {
            case .daily: return "daily"
            case .selectedWeekdays: return "selected_weekdays"
            case .timesPerWeek: return "times_per_week"
            }
        }()
        return [
            "group_id_input": groupID.uuidString,
            "title_input": draft.title,
            "activity_type_input": draft.activityName,
            "measurement_type_input": draft.measurementType.rawValue,
            "minimum_quantity_input": draft.minimumQuantity,
            "frequency_type_input": frequency,
            "scheduled_weekdays_input": Array(draft.scheduledWeekdays).sorted(),
            "duration_days_input": draft.durationDays,
            startKey: formatter.string(from: draft.startDate),
            "challenge_timezone_input": draft.timezone,
            "daily_deadline_minutes_input": draft.deadlineMinutes,
            "recovery_day_allowance_input": draft.recoveryDays
        ]
    }
}
