import Foundation

enum AppIdentity {
    static let name = "Cahoots"
    static var supportEmail: String { configured("CAHOOTS_SUPPORT_EMAIL", fallback: "support@cahoots.invalid") }
    static var inviteHost: String { configured("CAHOOTS_INVITE_HOST", fallback: "cahoots.invalid") }
    static var privacyURL: URL? { URL(string: configured("CAHOOTS_PRIVACY_URL", fallback: "")) }
    static var termsURL: URL? { URL(string: configured("CAHOOTS_TERMS_URL", fallback: "")) }

    private static func configured(_ key: String, fallback: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty, !value.hasPrefix("$(") else { return fallback }
        return value
    }
}

enum AppMode: String, Codable, Sendable {
    case demo
    case live
}

enum GroupRole: String, Codable, CaseIterable, Sendable {
    case owner, admin, member
}

enum MembershipStatus: String, Codable, Sendable {
    case active, removed, left
}

enum NotificationLevel: String, Codable, CaseIterable, Sendable {
    case immediate, digest, off
}

enum MeasurementType: String, Codable, CaseIterable, Identifiable, Sendable {
    case repetitions, seconds, minutes, distance

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .repetitions: "repetitions"
        case .seconds: "seconds"
        case .minutes: "minutes"
        case .distance: "kilometres"
        }
    }

    var shortName: String {
        switch self {
        case .repetitions: "reps"
        case .seconds: "sec"
        case .minutes: "min"
        case .distance: "km"
        }
    }

    /// Minutes and distance use a start clip plus a finish clip in one check-in.
    var requiresTwoClips: Bool {
        switch self {
        case .minutes, .distance: true
        case .repetitions, .seconds: false
        }
    }
}

enum WorkoutClipKind: String, Codable, Sendable {
    case set, start, finish
}

struct WorkoutClip: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var kind: WorkoutClipKind
    var durationSeconds: Double
    var localFilename: String?
    var remotePath: String?
    var createdAt: Date
}

enum FrequencyType: String, Codable, CaseIterable, Identifiable, Sendable {
    case daily
    case selectedWeekdays
    case timesPerWeek

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .daily: "Every day"
        case .selectedWeekdays: "Selected weekdays"
        case .timesPerWeek: "Times per week"
        }
    }
}

enum ProposalStatus: String, Codable, Sendable {
    case draft, voting, passed, failed, cancelled
}

enum VoteChoice: String, Codable, CaseIterable, Sendable {
    case accept, reject
}

enum ChallengeStatus: String, Codable, Sendable {
    case scheduled, active, completed, cancelled
}

enum SyncState: String, Codable, CaseIterable, Sendable {
    case synced, waiting, failed, rejected

    var label: String {
        switch self {
        case .synced: "Synced"
        case .waiting: "Waiting to sync"
        case .failed: "Sync failed"
        case .rejected: "Rejected by server"
        }
    }
}

enum PendingOperationKind: String, Codable, Sendable {
    case submission
}

enum VerificationState: String, Codable, Sendable {
    case honourSystem, accepted, rejected
}

enum ScoreEventType: String, Codable, Sendable {
    case requirementCompleted, bonus, adjustment
}

enum ActivityEventType: String, Codable, Sendable {
    case completion, recovery, proposal, voteCompleted, challengeStarted, roundFinished, memberJoined
}

enum AppearancePreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum Entitlement: String, Codable, Sendable {
    case free, plus, groupPro
}

struct CahootsUser: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var appleSubjectID: String?
    var displayName: String
    var avatarPath: String?
    var timezoneIdentifier: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var showsExactTotals: Bool

    var initials: String {
        let components = displayName.split(separator: " ")
        return components.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}

struct CahootsGroup: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var emoji: String
    var ownerID: UUID
    var memberLimit: Int
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?
}

struct GroupMembership: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var groupID: UUID
    var userID: UUID
    var role: GroupRole
    var status: MembershipStatus
    var joinedAt: Date
    var leftAt: Date?
    var notificationLevel: NotificationLevel
}

struct GroupInvite: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var groupID: UUID
    var code: String
    var createdBy: UUID
    var expiresAt: Date
    var maximumUses: Int
    var useCount: Int
    var revokedAt: Date?
}

struct ChallengeProposal: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var groupID: UUID
    var proposedBy: UUID
    var title: String
    var activityType: String
    var measurementType: MeasurementType
    var minimumQuantity: Double
    var frequencyType: FrequencyType
    var scheduledWeekdays: Set<Int>
    var durationDays: Int
    var proposedStartDate: Date
    var challengeTimezone: String
    var dailyDeadlineMinutes: Int
    var recoveryDayAllowance: Int
    var votingStartsAt: Date
    var votingEndsAt: Date
    var eligibleVoterIDs: Set<UUID>
    var status: ProposalStatus
    var createdAt: Date
}

struct Vote: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var proposalID: UUID
    var userID: UUID
    var choice: VoteChoice
    var createdAt: Date
    var updatedAt: Date
}

struct CahootsChallenge: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var groupID: UUID
    var proposalID: UUID?
    var title: String
    var activityType: String
    var measurementType: MeasurementType
    var minimumQuantity: Double
    var frequencyType: FrequencyType
    var scheduledWeekdays: Set<Int>
    var timesPerWeek: Int?
    var startDate: Date
    var endDate: Date
    var challengeTimezone: String
    var dailyDeadlineMinutes: Int
    var recoveryDayAllowance: Int
    var status: ChallengeStatus
    var scoringVersion: Int
    var createdAt: Date

    var quantityLabel: String {
        minimumQuantity.formatted(.number.precision(.fractionLength(minimumQuantity.rounded() == minimumQuantity ? 0 : 1)))
    }

    var naturalLanguageSummary: String {
        let schedule = frequencyType == .daily ? "every day" : "on selected weekdays"
        let deadlineHour = dailyDeadlineMinutes / 60
        let deadlineMinute = dailyDeadlineMinutes % 60
        let time = String(format: "%02d:%02d", deadlineHour, deadlineMinute)
        let recovery = recoveryDayAllowance == 1 ? "One recovery day is available." : "\(recoveryDayAllowance) recovery days are available."
        return String(localized: "Complete at least \(quantityLabel) \(activityType.lowercased()) \(schedule) for \(Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0) days. Check-ins close at \(time) \(challengeTimezone) time. \(recovery)")
    }
}

struct Submission: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var clientGeneratedID: UUID
    var challengeID: UUID
    var userID: UUID
    var requirementDate: Date
    var quantity: Double
    var measurementType: MeasurementType
    var completedAt: Date
    var submittedAt: Date
    var syncState: SyncState
    var verificationState: VerificationState
    var createdAt: Date
    var updatedAt: Date
    var rejectionReason: String? = nil
    var clips: [WorkoutClip] = []
}

struct ScoreEvent: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var challengeID: UUID
    var userID: UUID
    var submissionID: UUID?
    var eventType: ScoreEventType
    var points: Int
    var reason: String
    var scoringVersion: Int
    var createdAt: Date
    var requirementDate: Date? = nil
    var scoringKey: String? = nil
    var completionDelta: Int? = nil
}

struct NotificationPreference: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var userID: UUID
    var groupID: UUID?
    var personalRemindersEnabled: Bool
    var friendActivityMode: NotificationLevel
    var challengeUpdatesEnabled: Bool
    var quietHoursStart: Int
    var quietHoursEnd: Int
    var reminderMinutes: Int
}

struct UserNotificationSettings: Codable, Hashable, Sendable {
    var quietHoursStart: Int
    var quietHoursEnd: Int
    var defaultReminderMinutes: Int
    var primerDismissed: Bool
    var groups: [GroupNotificationSettings]

    static func defaults(userID: UUID, groups: [CahootsGroup]) -> UserNotificationSettings {
        .init(
            quietHoursStart: 22 * 60,
            quietHoursEnd: 7 * 60,
            defaultReminderMinutes: 18 * 60,
            primerDismissed: false,
            groups: groups.map { .defaults(groupID: $0.id) }
        )
    }

    func preference(for groupID: UUID) -> GroupNotificationSettings {
        groups.first { $0.groupID == groupID } ?? .defaults(groupID: groupID)
    }
}

struct GroupNotificationSettings: Identifiable, Codable, Hashable, Sendable {
    var id: UUID { groupID }
    var groupID: UUID
    var personalRemindersEnabled: Bool
    var friendActivityMode: NotificationLevel
    var challengeUpdatesEnabled: Bool
    var reminderMinutes: Int?

    static func defaults(groupID: UUID) -> GroupNotificationSettings {
        .init(groupID: groupID, personalRemindersEnabled: true, friendActivityMode: .digest, challengeUpdatesEnabled: true, reminderMinutes: nil)
    }
}

struct PendingSyncOperation: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var clientGeneratedID: UUID
    var kind: PendingOperationKind
    var retryCount: Int
    var nextRetryAt: Date
    var createdAt: Date
    var lastError: String?
}

struct RecoveryDayUsage: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var challengeID: UUID
    var userID: UUID
    var requirementDate: Date
    var createdAt: Date
}

struct LeaderboardEntry: Identifiable, Codable, Hashable, Sendable {
    var id: UUID { user.id }
    var user: CahootsUser
    var points: Int
    var completedRequirements: Int
    var scheduledRequirements: Int
    var currentStreak: Int
    var longestStreak: Int
    var finalScoreAchievedAt: Date
    var previousRank: Int?
    var groupID: UUID? = nil
    var challengeID: UUID? = nil

    var completionPercentage: Int {
        guard scheduledRequirements > 0 else { return 0 }
        return Int((Double(completedRequirements) / Double(scheduledRequirements) * 100).rounded())
    }
}

struct ActivityFeedItem: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var groupID: UUID
    var actorID: UUID?
    var actorName: String
    var eventType: ActivityEventType
    var message: String
    var createdAt: Date
}

struct DevicePushToken: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var userID: UUID
    var token: String
    var environment: String
    var createdAt: Date
}

struct Report: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var reporterID: UUID
    var reportedUserID: UUID
    var groupID: UUID
    var reason: String
    var createdAt: Date
}

struct BlockedUser: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var blockerID: UUID
    var blockedUserID: UUID
    var createdAt: Date
}

struct PreviousChallengeSummary: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var winnerName: String
    var topThree: [LeaderboardEntry]
    var totalCompletions: Int
    var personalBest: Int
}

struct MemberChallengeResult: Identifiable, Codable, Hashable, Sendable {
    var id: UUID { user.id }
    var user: CahootsUser
    var completionRate: Int
    var points: Int
    var longestStreak: Int
}

struct CahootsResult: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var groupID: UUID
    var challengeID: UUID
    var title: String
    var winnerName: String
    var topThree: [LeaderboardEntry]
    var members: [MemberChallengeResult]
    var totalCompletions: Int
    var personalBest: Int
    var completedAt: Date
}

struct DemoSnapshot: Codable, Sendable {
    var schemaVersion: Int? = nil
    var currentUser: CahootsUser
    var users: [CahootsUser]
    var groups: [CahootsGroup]
    var memberships: [GroupMembership]
    var invites: [GroupInvite]
    var challenges: [CahootsChallenge]
    var proposals: [ChallengeProposal]
    var votes: [Vote]
    var submissions: [Submission]
    var scoreEvents: [ScoreEvent]
    var leaderboard: [LeaderboardEntry]
    var allTimeLeaderboard: [LeaderboardEntry]
    var activity: [ActivityFeedItem]
    var notificationPreference: NotificationPreference
    var notificationSettings: UserNotificationSettings? = nil
    var pendingOperations: [PendingSyncOperation]
    var recoveryDays: [RecoveryDayUsage] = []
    var previousRound: PreviousChallengeSummary?
    var roundResults: [CahootsResult]? = nil
    var appearance: AppearancePreference
    var reports: [Report] = []
    var blockedUsers: [BlockedUser] = []
}

struct ActivityTemplate: Identifiable, Hashable, Sendable {
    let id: String
    let symbol: String
    let displayName: String
    let activityName: String
    let measurementType: MeasurementType
    let description: String
    let suggestedTarget: Double

    static let all: [ActivityTemplate] = [
        .init(id: "pushups", symbol: "figure.strengthtraining.traditional", displayName: "Push-ups", activityName: "push-ups", measurementType: .repetitions, description: "A familiar upper-body movement.", suggestedTarget: 15),
        .init(id: "squats", symbol: "figure.strengthtraining.functional", displayName: "Squats", activityName: "squats", measurementType: .repetitions, description: "A controlled lower-body movement.", suggestedTarget: 20),
        .init(id: "situps", symbol: "figure.core.training", displayName: "Sit-ups", activityName: "sit-ups", measurementType: .repetitions, description: "A short core-focused set.", suggestedTarget: 15),
        .init(id: "plank", symbol: "figure.cooldown", displayName: "Plank", activityName: "plank seconds", measurementType: .seconds, description: "Hold a comfortable, steady position.", suggestedTarget: 30),
        .init(id: "stretch", symbol: "figure.flexibility", displayName: "Stretching", activityName: "stretching minutes", measurementType: .minutes, description: "Unhurried mobility and recovery.", suggestedTarget: 10),
        .init(id: "walk-time", symbol: "figure.walk", displayName: "Walking · time", activityName: "walking minutes", measurementType: .minutes, description: "An easy walk at your own pace.", suggestedTarget: 20),
        .init(id: "walk-distance", symbol: "figure.walk.motion", displayName: "Walking · distance", activityName: "walking kilometres", measurementType: .distance, description: "Track a comfortable walking distance.", suggestedTarget: 2),
        .init(id: "run-time", symbol: "figure.run", displayName: "Running · time", activityName: "running minutes", measurementType: .minutes, description: "A run at a sustainable pace.", suggestedTarget: 15),
        .init(id: "run-distance", symbol: "figure.run.circle", displayName: "Running · distance", activityName: "running kilometres", measurementType: .distance, description: "Choose a reasonable distance.", suggestedTarget: 2),
        .init(id: "cycling", symbol: "figure.outdoor.cycle", displayName: "Cycling", activityName: "cycling minutes", measurementType: .minutes, description: "Indoor or outdoor cycling.", suggestedTarget: 20),
        .init(id: "custom", symbol: "slider.horizontal.3", displayName: "Custom activity", activityName: "activity", measurementType: .repetitions, description: "Define a neutral, measurable activity.", suggestedTarget: 10)
    ]
}
