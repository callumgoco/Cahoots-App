import Foundation
import UserNotifications

enum CahootsNotificationKind: String, Codable, Sendable {
    case daily, evening, deadline, vote

    var priority: Int {
        switch self {
        case .vote: 0
        case .deadline: 1
        case .evening: 2
        case .daily: 3
        }
    }
}

struct NotificationPlanItem: Identifiable, Hashable, Sendable {
    var id: String
    var kind: CahootsNotificationKind
    var fireDate: Date
    var groupID: UUID
    var challengeID: UUID?
    var proposalID: UUID?
}

protocol NotificationScheduling: Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func replacePlan(_ plan: [NotificationPlanItem]) async
    func pendingIdentifiers() async -> [String]
}

actor NotificationService: NotificationScheduling {
    private let identifierPrefix = AppDefaults.notificationPrefix
    private let legacyIdentifierPrefix = AppDefaults.legacyNotificationPrefix

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
    }

    func replacePlan(_ plan: [NotificationPlanItem]) async {
        let center = UNUserNotificationCenter.current()
        let existing = await center.pendingNotificationRequests().map(\.identifier).filter {
            $0.hasPrefix(identifierPrefix) || $0.hasPrefix(legacyIdentifierPrefix)
        }
        center.removePendingNotificationRequests(withIdentifiers: existing)
        for item in plan where item.fireDate > .now {
            let content = content(for: item.kind)
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(.init(identifier: item.id, content: content, trigger: trigger))
        }
    }

    func pendingIdentifiers() async -> [String] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)
    }

    private func content(for kind: CahootsNotificationKind) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.sound = .default
        switch kind {
        case .daily:
            content.title = String(localized: "Your Cahoots check-in")
            content.body = String(localized: "A scheduled requirement is ready when you are.")
        case .evening:
            content.title = String(localized: "A check-in is still open")
            content.body = String(localized: "There is still time to check in today.")
        case .deadline:
            content.title = String(localized: "Today’s challenge closes soon")
            content.body = String(localized: "Your scheduled check-in window closes in 30 minutes.")
        case .vote:
            content.title = String(localized: "Voting closes soon")
            content.body = String(localized: "Review the group proposal before voting closes.")
        }
        return content
    }
}

enum NotificationPlanBuilder {
    static func build(snapshot: DemoSnapshot, now: Date, maximumCount: Int = 60) -> [NotificationPlanItem] {
        let settings = snapshot.notificationSettings ?? UserNotificationSettings.defaults(userID: snapshot.currentUser.id, groups: snapshot.groups)
        let activeGroupIDs = Set(snapshot.memberships.filter {
            $0.userID == snapshot.currentUser.id && $0.status == .active
        }.map(\.groupID))
        var candidates: [NotificationPlanItem] = []

        for challenge in snapshot.challenges where activeGroupIDs.contains(challenge.groupID) && (challenge.status == .active || challenge.status == .scheduled) {
            let groupSettings = settings.preference(for: challenge.groupID)
            guard groupSettings.personalRemindersEnabled,
                  let calendar = ScheduleEngine.calendar(for: challenge),
                  let horizon = calendar.date(byAdding: .day, value: 7, to: now) else { continue }
            let reminderMinutes = groupSettings.reminderMinutes ?? settings.defaultReminderMinutes
            for requirementDate in ScheduleEngine.scheduledDates(for: challenge, through: horizon) {
                guard let deadline = ScheduleEngine.deadline(for: requirementDate, challenge: challenge), deadline > now else { continue }
                let completed = snapshot.submissions.contains {
                    $0.challengeID == challenge.id && $0.userID == snapshot.currentUser.id && $0.syncState != .rejected &&
                    ScheduleEngine.isSameRequirementDay($0.requirementDate, requirementDate, challenge: challenge) &&
                    ScoringEngine.points(completedQuantity: $0.quantity, minimumQuantity: challenge.minimumQuantity) > 0
                }
                let recovered = snapshot.recoveryDays.contains {
                    $0.challengeID == challenge.id && $0.userID == snapshot.currentUser.id &&
                    ScheduleEngine.isSameRequirementDay($0.requirementDate, requirementDate, challenge: challenge)
                }
                let day = calendar.startOfDay(for: requirementDate)
                if let reminder = calendar.date(byAdding: .minute, value: reminderMinutes, to: day), reminder > now {
                    append(.daily, at: reminder, deadline: deadline, groupID: challenge.groupID, challengeID: challenge.id, proposalID: nil, settings: settings, to: &candidates)
                }
                if !completed && !recovered {
                    append(.evening, at: deadline.addingTimeInterval(-2 * 3_600), deadline: deadline, groupID: challenge.groupID, challengeID: challenge.id, proposalID: nil, settings: settings, to: &candidates)
                    append(.deadline, at: deadline.addingTimeInterval(-30 * 60), deadline: deadline, groupID: challenge.groupID, challengeID: challenge.id, proposalID: nil, settings: settings, to: &candidates)
                }
            }
        }

        for proposal in snapshot.proposals where activeGroupIDs.contains(proposal.groupID) && proposal.status == .voting {
            let groupSettings = settings.preference(for: proposal.groupID)
            guard groupSettings.challengeUpdatesEnabled,
                  !snapshot.votes.contains(where: { $0.proposalID == proposal.id && $0.userID == snapshot.currentUser.id }),
                  proposal.votingEndsAt.timeIntervalSince(now) >= 10 * 60 else { continue }
            let preferred = proposal.votingEndsAt.addingTimeInterval(-4 * 3_600)
            let fireDate = preferred > now ? preferred : now.addingTimeInterval(60)
            append(.vote, at: fireDate, deadline: proposal.votingEndsAt, groupID: proposal.groupID, challengeID: nil, proposalID: proposal.id, settings: settings, to: &candidates)
        }

        return candidates
            .filter { $0.fireDate > now }
            .sorted { $0.fireDate == $1.fireDate ? $0.kind.priority < $1.kind.priority : $0.fireDate < $1.fireDate }
            .prefix(maximumCount)
            .map { $0 }
    }

    private static func append(
        _ kind: CahootsNotificationKind,
        at proposedDate: Date,
        deadline: Date,
        groupID: UUID,
        challengeID: UUID?,
        proposalID: UUID?,
        settings: UserNotificationSettings,
        to candidates: inout [NotificationPlanItem]
    ) {
        guard let fireDate = adjustedForQuietHours(proposedDate, deadline: deadline, settings: settings), fireDate < deadline else { return }
        let dateToken = ISO8601DateFormatter().string(from: fireDate)
        let subject = challengeID?.uuidString ?? proposalID?.uuidString ?? "general"
        candidates.append(.init(
            id: "\(AppDefaults.notificationPrefix)\(kind.rawValue).\(groupID.uuidString).\(subject).\(dateToken)",
            kind: kind, fireDate: fireDate, groupID: groupID,
            challengeID: challengeID, proposalID: proposalID
        ))
    }

    private static func adjustedForQuietHours(_ date: Date, deadline: Date, settings: UserNotificationSettings) -> Date? {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let minute = (calendar.component(.hour, from: date) * 60) + calendar.component(.minute, from: date)
        let start = settings.quietHoursStart
        let end = settings.quietHoursEnd
        let inQuietHours = start <= end ? (minute >= start && minute < end) : (minute >= start || minute < end)
        guard inQuietHours else { return date }
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = end / 60
        components.minute = end % 60
        guard var shifted = calendar.date(from: components) else { return nil }
        if start > end && minute >= start { shifted = calendar.date(byAdding: .day, value: 1, to: shifted) ?? shifted }
        return shifted < deadline ? shifted : nil
    }
}
