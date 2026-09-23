import Foundation

enum TodayMemberStatus: Equatable, Sendable {
    case done
    case rest
    case pending
}

struct TodayMemberStatusEntry: Identifiable, Equatable, Sendable {
    var id: UUID { user.id }
    let user: CahootsUser
    let status: TodayMemberStatus
    let isCurrentUser: Bool
}

enum TodayCrewStatusBuilder {
    static func statuses(
        members: [CahootsUser],
        submissions: [Submission],
        recoveries: [RecoveryDayUsage],
        challenge: CahootsChallenge,
        now: Date,
        currentUserID: UUID
    ) -> [TodayMemberStatusEntry] {
        let emphasizePending = Self.emphasizePending(now: now, challenge: challenge)
        return members.map { user in
            let status = status(
                for: user.id,
                submissions: submissions,
                recoveries: recoveries,
                challenge: challenge,
                now: now
            )
            return TodayMemberStatusEntry(
                user: user,
                status: status,
                isCurrentUser: user.id == currentUserID
            )
        }
        .sorted { lhs, rhs in
            if lhs.isCurrentUser != rhs.isCurrentUser { return lhs.isCurrentUser }
            return statusSortRank(lhs.status, emphasizePending: emphasizePending)
                < statusSortRank(rhs.status, emphasizePending: emphasizePending)
        }
    }

    private static func emphasizePending(now: Date, challenge: CahootsChallenge) -> Bool {
        guard let calendar = ScheduleEngine.calendar(for: challenge) else {
            return Calendar.current.component(.hour, from: now) >= 15
        }
        return calendar.component(.hour, from: now) >= 15
    }

    private static func status(
        for userID: UUID,
        submissions: [Submission],
        recoveries: [RecoveryDayUsage],
        challenge: CahootsChallenge,
        now: Date
    ) -> TodayMemberStatus {
        let usedRecovery = recoveries.contains {
            $0.challengeID == challenge.id
                && $0.userID == userID
                && ScheduleEngine.isSameRequirementDay($0.requirementDate, now, challenge: challenge)
        }
        if usedRecovery { return .rest }

        let done = submissions.contains {
            $0.challengeID == challenge.id
                && $0.userID == userID
                && $0.syncState != .rejected
                && ScheduleEngine.isSameRequirementDay($0.requirementDate, now, challenge: challenge)
                && ScoringEngine.points(
                    completedQuantity: $0.quantity,
                    minimumQuantity: challenge.minimumQuantity
                ) > 0
        }
        if done { return .done }
        return .pending
    }

    private static func statusSortRank(_ status: TodayMemberStatus, emphasizePending: Bool) -> Int {
        switch status {
        case .done: emphasizePending ? 2 : 0
        case .rest: 1
        case .pending: emphasizePending ? 0 : 2
        }
    }
}

/// Plain-language “who’s in / who’s left” copy. Never includes quantities or vote choices.
enum CrewAccountabilityCopy {
    static func checkInSummary(entries: [TodayMemberStatusEntry], nameLimit: Int = 3) -> String? {
        guard entries.count > 1 else { return nil }
        let accounted = entries.filter { $0.status == .done || $0.status == .rest }.count
        let pending = entries.filter { $0.status == .pending }
        if pending.isEmpty {
            return String(localized: "Everyone’s in for today.")
        }
        let names = pendingPrefix(pending, limit: nameLimit)
        if accounted == 0 {
            return String(localized: "Waiting on \(names).")
        }
        return String(localized: "\(accounted) of \(entries.count) done · \(stillNeedClause(names: names, action: .checkIn))")
    }

    static func stillNeedToCheckIn(entries: [TodayMemberStatusEntry], nameLimit: Int = 4) -> String? {
        let peers = entries.filter { !$0.isCurrentUser }
        let pendingPeers = peers.filter { $0.status == .pending }
        if pendingPeers.isEmpty {
            guard !peers.isEmpty else { return nil }
            return String(localized: "Everyone else is in.")
        }
        let names = pendingPrefix(pendingPeers, limit: nameLimit)
        return String(localized: "Still need to: \(names).")
    }

    static func voteSummary(
        eligible: [CahootsUser],
        votedUserIDs: Set<UUID>,
        currentUserID: UUID,
        nameLimit: Int = 3
    ) -> String? {
        guard eligible.count > 1 else { return nil }
        let outstanding = eligible.filter { !votedUserIDs.contains($0.id) }
        if outstanding.isEmpty {
            return String(localized: "Everyone has voted.")
        }
        let names = listNames(outstanding.map { displayName($0, currentUserID: currentUserID) }, limit: nameLimit)
        return String(localized: "\(votedUserIDs.count) of \(eligible.count) voted · \(stillNeedClause(names: names, action: .vote))")
    }

    static func eveningNudge(pendingOthers: Int) -> String {
        if pendingOthers <= 0 {
            return String(localized: "There is still time to check in today.")
        }
        if pendingOthers == 1 {
            return String(localized: "You and 1 other still need to check in.")
        }
        return String(localized: "You and \(pendingOthers) others still need to check in.")
    }

    private enum OutstandingAction {
        case checkIn
        case vote
    }

    /// Completes “… still need(s) to check in / vote.” with correct singular/plural grammar.
    private static func stillNeedClause(names: String, action: OutstandingAction) -> String {
        let isYou = names == String(localized: "You")
        let isSingularPerson = isYou || (!names.contains(" and ") && !names.contains(", "))
        switch (action, isYou, isSingularPerson) {
        case (.checkIn, true, _):
            return String(localized: "You still need to check in.")
        case (.vote, true, _):
            return String(localized: "You still need to vote.")
        case (.checkIn, false, true):
            return String(localized: "\(names) still needs to check in.")
        case (.vote, false, true):
            return String(localized: "\(names) still needs to vote.")
        case (.checkIn, false, false):
            return String(localized: "\(names) still need to check in.")
        case (.vote, false, false):
            return String(localized: "\(names) still need to vote.")
        }
    }

    private static func pendingPrefix(_ pending: [TodayMemberStatusEntry], limit: Int) -> String {
        listNames(
            pending.map { entry in
                if entry.isCurrentUser { return String(localized: "You") }
                return entry.user.displayName.split(separator: " ").first.map(String.init) ?? entry.user.displayName
            },
            limit: limit
        )
    }

    private static func displayName(_ user: CahootsUser, currentUserID: UUID) -> String {
        if user.id == currentUserID { return String(localized: "You") }
        return user.displayName.split(separator: " ").first.map(String.init) ?? user.displayName
    }

    private static func listNames(_ names: [String], limit: Int) -> String {
        let unique = Array(names.prefix(limit))
        let overflow = names.count - unique.count
        if overflow > 0 {
            return unique.joined(separator: ", ") + String(localized: ", +\(overflow) more")
        }
        switch unique.count {
        case 0: return ""
        case 1: return unique[0]
        case 2: return String(localized: "\(unique[0]) and \(unique[1])")
        default:
            let head = unique.dropLast().joined(separator: ", ")
            return String(localized: "\(head), and \(unique.last!)")
        }
    }
}

enum RoundProgress {
    /// Requirement-day index within the challenge schedule (1-based), plus total scheduled days.
    static func dayOfRound(challenge: CahootsChallenge, now: Date) -> (current: Int, total: Int)? {
        let dates = ScheduleEngine.scheduledDates(for: challenge)
        guard !dates.isEmpty, let calendar = ScheduleEngine.calendar(for: challenge) else { return nil }
        let today = calendar.startOfDay(for: now)
        let total = dates.count
        if let index = dates.firstIndex(where: { calendar.isDate($0, inSameDayAs: today) }) {
            return (index + 1, total)
        }
        let elapsed = dates.filter { $0 <= today }.count
        if elapsed == 0 { return (1, total) }
        return (min(elapsed, total), total)
    }

    static func dayLabel(challenge: CahootsChallenge, now: Date) -> String? {
        guard let progress = dayOfRound(challenge: challenge, now: now) else { return nil }
        return String(localized: "Day \(progress.current) of \(progress.total)")
    }
}
