import Foundation

enum ScoringEngine {
    static func points(completedQuantity: Double, minimumQuantity: Double) -> Int {
        guard minimumQuantity > 0, completedQuantity >= minimumQuantity else { return 0 }
        let extraRatio = max(0, completedQuantity - minimumQuantity) / minimumQuantity
        let bonus = min(10, Int(floor(extraRatio * 15)))
        return 100 + bonus
    }
}

enum WorkoutClipRules {
    static let minimumDuration: TimeInterval = 2
    static let maximumDuration: TimeInterval = 10 * 60

    static func requiredKinds(for measurement: MeasurementType) -> [WorkoutClipKind] {
        measurement.requiresTwoClips ? [.start, .finish] : [.set]
    }

    static func areValid(_ clips: [WorkoutClip], for measurement: MeasurementType) -> Bool {
        let required = requiredKinds(for: measurement)
        guard Set(clips.map(\.kind)) == Set(required), clips.count == required.count else { return false }
        return clips.allSatisfy { clip in
            clip.durationSeconds >= minimumDuration
                && clip.durationSeconds <= maximumDuration
                && (clip.localFilename != nil || clip.remotePath != nil)
        }
    }
}

enum CheckInSubmissionRules {
    static let closedWindowMessage = String(localized: "Today’s check-in window is closed.")

    /// Whether the check-in window is open for `now` on the challenge's scheduled day.
    static func isWindowOpen(challenge: RoundChallenge, at now: Date) -> Bool {
        guard challenge.status == .active,
              ScheduleEngine.isScheduled(on: now, challenge: challenge),
              let deadline = ScheduleEngine.deadline(for: now, challenge: challenge) else { return false }
        return deadline >= now
    }

    /// Requirement day to credit. Prefer a date pinned when the session opened while the window was open.
    static func requirementDate(
        challenge: RoundChallenge,
        now: Date,
        pinnedRequirementDate: Date?
    ) -> Date {
        pinnedRequirementDate
            ?? ScheduleEngine.requirementDay(for: now, challenge: challenge)
            ?? now
    }

    /// Returns a localized validation message, or `nil` if submit is allowed.
    /// When `openedWhileWindowOpen` is true, the pinned day is credited even if `now` is past that day's deadline.
    static func validationMessage(
        challenge: RoundChallenge,
        now: Date,
        pinnedRequirementDate: Date?,
        openedWhileWindowOpen: Bool
    ) -> String? {
        guard challenge.status == .active else {
            return String(localized: "This round is no longer available.")
        }
        let day = requirementDate(challenge: challenge, now: now, pinnedRequirementDate: pinnedRequirementDate)
        guard ScheduleEngine.isScheduled(on: day, challenge: challenge) else {
            return closedWindowMessage
        }
        if openedWhileWindowOpen { return nil }
        guard let deadline = ScheduleEngine.deadline(for: day, challenge: challenge), deadline >= now else {
            return closedWindowMessage
        }
        return nil
    }
}

enum CheckInVisibility {
    static func canRevealToday(
        viewerHasCompleted: Bool,
        usedRecovery: Bool,
        now: Date,
        deadline: Date?
    ) -> Bool {
        if viewerHasCompleted || usedRecovery { return true }
        if let deadline, now >= deadline { return true }
        return false
    }

    static func redacted(_ submission: Submission, reveal: Bool) -> Submission {
        guard !reveal else { return submission }
        var copy = submission
        copy.quantity = 0
        copy.clips = copy.clips.map { clip in
            var hidden = clip
            hidden.localFilename = nil
            hidden.remotePath = nil
            return hidden
        }
        return copy
    }

    /// Points earned today by a peer that should stay hidden until the viewer unlocks spoilers.
    static func todayPointsToHide(
        submission: Submission,
        challenge: RoundChallenge,
        viewerUserID: UUID,
        canReveal: Bool
    ) -> Int {
        guard !canReveal, submission.userID != viewerUserID else { return 0 }
        return ScoringEngine.points(completedQuantity: submission.quantity, minimumQuantity: challenge.minimumQuantity)
    }
}

enum VotingOutcome: Equatable {
    case open
    case passed
    case failed
}

enum VotingEngine {
    static func outcome(eligibleVoters: Int, choices: [VoteChoice], now: Date, closesAt: Date) -> VotingOutcome {
        guard eligibleVoters >= 2 else { return .failed }
        guard choices.count >= eligibleVoters || now >= closesAt else { return .open }
        let accepts = choices.filter { $0 == .accept }.count
        let strictMajority = eligibleVoters / 2 + 1
        return accepts >= max(2, strictMajority) ? .passed : .failed
    }

    static func upsert(choice: VoteChoice, userID: UUID, proposalID: UUID, votes: inout [Vote], now: Date = .now) {
        if let index = votes.firstIndex(where: { $0.userID == userID && $0.proposalID == proposalID }) {
            votes[index].choice = choice
            votes[index].updatedAt = now
        } else {
            votes.append(.init(id: UUID(), proposalID: proposalID, userID: userID, choice: choice, createdAt: now, updatedAt: now))
        }
    }
}

enum ScheduleEngine {
    static func calendar(for challenge: RoundChallenge) -> Calendar? {
        guard let timezone = TimeZone(identifier: challenge.challengeTimezone) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        return calendar
    }

    static func requirementDay(for date: Date, challenge: RoundChallenge) -> Date? {
        calendar(for: challenge)?.startOfDay(for: date)
    }

    static func isSameRequirementDay(_ first: Date, _ second: Date, challenge: RoundChallenge) -> Bool {
        guard let calendar = calendar(for: challenge) else { return false }
        return calendar.isDate(first, inSameDayAs: second)
    }

    static func startInstant(for challenge: RoundChallenge) -> Date? {
        calendar(for: challenge)?.startOfDay(for: challenge.startDate)
    }

    static func completionInstant(for challenge: RoundChallenge) -> Date? {
        deadline(for: challenge.endDate, challenge: challenge)
    }

    static func isScheduled(on date: Date, challenge: RoundChallenge) -> Bool {
        guard let calendar = calendar(for: challenge) else { return false }
        let start = calendar.startOfDay(for: challenge.startDate)
        let end = calendar.startOfDay(for: challenge.endDate)
        let day = calendar.startOfDay(for: date)
        guard day >= start, day <= end else { return false }

        switch challenge.frequencyType {
        case .daily:
            return true
        case .selectedWeekdays:
            return challenge.scheduledWeekdays.contains(calendar.component(.weekday, from: day))
        case .timesPerWeek:
            return true
        }
    }

    static func deadline(for requirementDate: Date, challenge: RoundChallenge) -> Date? {
        guard let calendar = calendar(for: challenge) else { return nil }
        let start = calendar.startOfDay(for: requirementDate)
        return calendar.date(byAdding: .minute, value: challenge.dailyDeadlineMinutes, to: start)
    }

    static func scheduledDates(for challenge: RoundChallenge, through end: Date? = nil) -> [Date] {
        guard let calendar = calendar(for: challenge) else { return [] }
        var cursor = calendar.startOfDay(for: challenge.startDate)
        let finalDate = min(calendar.startOfDay(for: end ?? challenge.endDate), calendar.startOfDay(for: challenge.endDate))
        var dates: [Date] = []
        while cursor <= finalDate {
            if isScheduled(on: cursor, challenge: challenge) { dates.append(cursor) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return dates
    }
}

enum StreakEngine {
    static func currentStreak(scheduledDates: [Date], completedDates: Set<Date>, recoveryDates: Set<Date>, calendar: Calendar = .current) -> Int {
        let normalizedCompleted = Set(completedDates.map { calendar.startOfDay(for: $0) })
        let normalizedRecovery = Set(recoveryDates.map { calendar.startOfDay(for: $0) })
        var streak = 0
        for date in scheduledDates.map({ calendar.startOfDay(for: $0) }).sorted(by: >) {
            if normalizedCompleted.contains(date) {
                streak += 1
            } else if normalizedRecovery.contains(date) {
                continue
            } else {
                break
            }
        }
        return streak
    }
}

enum LeaderboardEngine {
    static func ranked(_ entries: [LeaderboardEntry]) -> [LeaderboardEntry] {
        entries.sorted {
            if $0.points != $1.points { return $0.points > $1.points }
            if $0.completedRequirements != $1.completedRequirements { return $0.completedRequirements > $1.completedRequirements }
            if $0.longestStreak != $1.longestStreak { return $0.longestStreak > $1.longestStreak }
            return $0.finalScoreAchievedAt < $1.finalScoreAchievedAt
        }
    }
}

enum InviteEngine {
    static func validation(invite: GroupInvite, memberCount: Int, now: Date = .now) -> InviteValidation {
        if invite.revokedAt != nil || invite.expiresAt <= now { return .expired }
        if invite.useCount >= invite.maximumUses { return .expired }
        if memberCount >= 20 { return .groupFull }
        return .valid
    }
}

enum InviteValidation: Equatable {
    case valid, expired, groupFull
}

enum MembershipRules {
    static func canLeave(role: GroupRole, activeMemberCount: Int) -> Bool {
        role != .owner || activeMemberCount <= 1
    }
}

enum GroupPermissionRules {
    static func canRemove(actor: GroupRole, target: GroupRole) -> Bool {
        guard target != .owner else { return false }
        return actor == .owner || (actor == .admin && target == .member)
    }

    static func canManageInvites(_ role: GroupRole) -> Bool {
        role == .owner || role == .admin
    }

    static func canChangeRoles(_ role: GroupRole) -> Bool { role == .owner }
    static func canEditSettings(_ role: GroupRole) -> Bool { role == .owner }
}

enum TextSanitizer {
    static func clean(_ input: String, maximumLength: Int = 60) -> String {
        let collapsed = input
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(collapsed.prefix(maximumLength))
    }
}
