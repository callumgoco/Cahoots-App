import Foundation

struct RequirementKey: Hashable, Codable, Sendable {
    let challengeID: UUID
    let userID: UUID
    let year: Int
    let month: Int
    let day: Int

    init?(challenge: RoundChallenge, userID: UUID, date: Date) {
        guard let timezone = TimeZone(identifier: challenge.challengeTimezone) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        self.challengeID = challenge.id
        self.userID = userID
        self.year = year
        self.month = month
        self.day = day
    }

    var dateToken: String { String(format: "%04d-%02d-%02d", year, month, day) }
}

enum RoundDomainEvent: Equatable, Sendable {
    case votePassed(UUID)
    case voteFailed(UUID)
    case challengeStarted(UUID)
    case challengeCompleted(UUID)
}

struct ReconciliationResult: Sendable {
    var snapshot: DemoSnapshot
    var events: [RoundDomainEvent]
    var nextBoundary: Date?
}

enum LeaderboardLedger {
    static func refresh(in snapshot: inout DemoSnapshot) {
        for index in snapshot.leaderboard.indices {
            guard let challengeID = snapshot.leaderboard[index].challengeID else { continue }
            let userID = snapshot.leaderboard[index].user.id
            let events = snapshot.scoreEvents.filter { $0.challengeID == challengeID && $0.userID == userID }
            guard !events.isEmpty else { continue }
            snapshot.leaderboard[index].points = events.reduce(0) { $0 + $1.points }
            snapshot.leaderboard[index].completedRequirements = events.reduce(0) { partial, event in
                partial + (event.completionDelta ?? (event.eventType == .requirementCompleted ? 1 : 0))
            }
            if let latest = events.map(\.createdAt).max() {
                snapshot.leaderboard[index].finalScoreAchievedAt = latest
            }
        }
    }
}

enum RoundStateReconciler {
    static func reconcile(snapshot source: DemoSnapshot, at now: Date) -> ReconciliationResult {
        var snapshot = source
        var events: [RoundDomainEvent] = []
        var boundaries: [Date] = []
        LeaderboardLedger.refresh(in: &snapshot)
        refreshStreaks(in: &snapshot, at: now)

        for proposalIndex in snapshot.proposals.indices where snapshot.proposals[proposalIndex].status == .voting {
            let proposal = snapshot.proposals[proposalIndex]
            let eligibleVotes = snapshot.votes
                .filter { $0.proposalID == proposal.id && proposal.eligibleVoterIDs.contains($0.userID) }
                .reduce(into: [UUID: VoteChoice]()) { $0[$1.userID] = $1.choice }
            let outcome = VotingEngine.outcome(
                eligibleVoters: proposal.eligibleVoterIDs.count,
                choices: Array(eligibleVotes.values),
                now: now,
                closesAt: proposal.votingEndsAt
            )
            switch outcome {
            case .open:
                boundaries.append(proposal.votingEndsAt)
            case .passed:
                snapshot.proposals[proposalIndex].status = .passed
                events.append(.votePassed(proposal.id))
                if !snapshot.challenges.contains(where: { $0.proposalID == proposal.id }) {
                    let challenge = ChallengeFactory.makeChallenge(from: proposal, createdAt: now)
                    snapshot.challenges.append(challenge)
                    ChallengeFactory.seedLeaderboardEntries(for: challenge, in: &snapshot, at: now)
                }
                addActivityIfNeeded(
                    to: &snapshot, groupID: proposal.groupID, type: .voteCompleted,
                    message: "The proposal passed and is now scheduled.", at: now
                )
            case .failed:
                snapshot.proposals[proposalIndex].status = .failed
                events.append(.voteFailed(proposal.id))
                addActivityIfNeeded(
                    to: &snapshot, groupID: proposal.groupID, type: .voteCompleted,
                    message: "The proposal did not pass.", at: now
                )
            }
        }

        for challengeIndex in snapshot.challenges.indices {
            let challenge = snapshot.challenges[challengeIndex]
            guard challenge.status == .scheduled || challenge.status == .active else { continue }
            guard let startsAt = ScheduleEngine.startInstant(for: challenge),
                  let completesAt = ScheduleEngine.completionInstant(for: challenge) else { continue }

            if snapshot.challenges[challengeIndex].status == .scheduled {
                if now >= startsAt {
                    snapshot.challenges[challengeIndex].status = .active
                    events.append(.challengeStarted(challenge.id))
                    addActivityIfNeeded(
                        to: &snapshot, groupID: challenge.groupID, type: .challengeStarted,
                        message: "\(challenge.title) has started.", at: max(startsAt, challenge.createdAt)
                    )
                } else {
                    boundaries.append(startsAt)
                }
            }

            if now >= completesAt {
                snapshot.challenges[challengeIndex].status = .completed
                events.append(.challengeCompleted(challenge.id))
                addActivityIfNeeded(
                    to: &snapshot, groupID: challenge.groupID, type: .roundFinished,
                    message: "\(challenge.title) has finished.", at: completesAt
                )
                if !(snapshot.roundResults ?? []).contains(where: { $0.challengeID == challenge.id }) {
                    let result = makeResult(snapshot: snapshot, challenge: challenge, completedAt: completesAt)
                    snapshot.roundResults = (snapshot.roundResults ?? []) + [result]
                }
            } else {
                boundaries.append(completesAt)
            }
        }

        return .init(snapshot: snapshot, events: events, nextBoundary: boundaries.filter { $0 > now }.min())
    }

    private static func challengeEndDate(for proposal: ChallengeProposal) -> Date {
        ChallengeFactory.endDate(for: proposal)
    }

    private static func addActivityIfNeeded(
        to snapshot: inout DemoSnapshot,
        groupID: UUID,
        type: ActivityEventType,
        message: String,
        at date: Date
    ) {
        guard !snapshot.activity.contains(where: { $0.groupID == groupID && $0.eventType == type && $0.message == message }) else { return }
        snapshot.activity.insert(.init(id: UUID(), groupID: groupID, actorID: nil, actorName: AppIdentity.name, eventType: type, message: message, createdAt: date), at: 0)
    }

    private static func makeResult(snapshot: DemoSnapshot, challenge: RoundChallenge, completedAt: Date) -> RoundResult {
        let entries = LeaderboardEngine.ranked(snapshot.leaderboard.filter {
            ($0.groupID == challenge.groupID || $0.groupID == nil) && ($0.challengeID == challenge.id || $0.challengeID == nil)
        })
        let members = entries.map {
            MemberRoundResult(user: $0.user, completionRate: $0.completionPercentage, points: $0.points, longestStreak: $0.longestStreak)
        }
        let currentUserEntry = entries.first { $0.user.id == snapshot.currentUser.id }
        return .init(
            id: UUID(), groupID: challenge.groupID, challengeID: challenge.id,
            title: challenge.title, winnerName: entries.first?.user.displayName ?? "Round members",
            topThree: Array(entries.prefix(3)), members: members,
            totalCompletions: entries.reduce(0) { $0 + $1.completedRequirements },
            personalBest: currentUserEntry?.longestStreak ?? 0,
            completedAt: completedAt
        )
    }

    private static func refreshStreaks(in snapshot: inout DemoSnapshot, at now: Date) {
        for challenge in snapshot.challenges where challenge.status == .active || challenge.status == .completed {
            guard let calendar = ScheduleEngine.calendar(for: challenge) else { continue }
            for entryIndex in snapshot.leaderboard.indices where
                (snapshot.leaderboard[entryIndex].groupID == challenge.groupID || snapshot.leaderboard[entryIndex].groupID == nil) &&
                (snapshot.leaderboard[entryIndex].challengeID == challenge.id || snapshot.leaderboard[entryIndex].challengeID == nil) {
                let userID = snapshot.leaderboard[entryIndex].user.id
                let accepted = snapshot.submissions.filter {
                    $0.challengeID == challenge.id && $0.userID == userID && $0.verificationState == .accepted &&
                    ScoringEngine.points(completedQuantity: $0.quantity, minimumQuantity: challenge.minimumQuantity) > 0
                }
                let recoveries = snapshot.recoveryDays.filter { $0.challengeID == challenge.id && $0.userID == userID }
                let completedDates = Set(accepted.map { calendar.startOfDay(for: $0.requirementDate) })
                let recoveryDates = Set(recoveries.map { calendar.startOfDay(for: $0.requirementDate) })
                let evaluatedDates = ScheduleEngine.scheduledDates(for: challenge, through: now).filter { date in
                    let day = calendar.startOfDay(for: date)
                    return completedDates.contains(day) || recoveryDates.contains(day) || (ScheduleEngine.deadline(for: date, challenge: challenge) ?? .distantFuture) <= now
                }
                let streak = StreakEngine.currentStreak(scheduledDates: evaluatedDates, completedDates: completedDates, recoveryDates: recoveryDates, calendar: calendar)
                snapshot.leaderboard[entryIndex].currentStreak = streak
                snapshot.leaderboard[entryIndex].longestStreak = max(snapshot.leaderboard[entryIndex].longestStreak, streak)
            }
        }
    }
}

enum SnapshotMigrator {
    static func migrate(_ source: DemoSnapshot) -> DemoSnapshot {
        var snapshot = source
        if snapshot.schemaVersion != 2 && snapshot.schemaVersion != 3 {
            snapshot = migrateToV2(snapshot)
        }
        if snapshot.schemaVersion == 2 {
            snapshot = migrateToV3(snapshot)
        }
        ensureLedgerBaselines(in: &snapshot)
        LeaderboardLedger.refresh(in: &snapshot)
        return snapshot
    }

    private static func migrateToV2(_ source: DemoSnapshot) -> DemoSnapshot {
        var snapshot = source
        snapshot.schemaVersion = 2
        let currentUserGroupIDs = Set(snapshot.memberships.filter {
            $0.userID == snapshot.currentUser.id && $0.status == .active
        }.map(\.groupID))
        let primaryGroupID = snapshot.groups.first { currentUserGroupIDs.contains($0.id) }?.id
        let primaryChallengeID = snapshot.challenges.first { $0.groupID == primaryGroupID && ($0.status == .active || $0.status == .scheduled) }?.id
        for index in snapshot.leaderboard.indices {
            snapshot.leaderboard[index].groupID = snapshot.leaderboard[index].groupID ?? primaryGroupID
            snapshot.leaderboard[index].challengeID = snapshot.leaderboard[index].challengeID ?? primaryChallengeID
        }
        for index in snapshot.allTimeLeaderboard.indices {
            snapshot.allTimeLeaderboard[index].groupID = snapshot.allTimeLeaderboard[index].groupID ?? primaryGroupID
        }
        for index in snapshot.scoreEvents.indices {
            snapshot.scoreEvents[index].requirementDate = snapshot.scoreEvents[index].requirementDate ?? snapshot.scoreEvents[index].createdAt
            if snapshot.scoreEvents[index].scoringKey == nil,
               let date = snapshot.scoreEvents[index].requirementDate,
               let challenge = snapshot.challenges.first(where: { $0.id == snapshot.scoreEvents[index].challengeID }),
               let key = RequirementKey(challenge: challenge, userID: snapshot.scoreEvents[index].userID, date: date) {
                snapshot.scoreEvents[index].scoringKey = "\(key.challengeID.uuidString):\(key.userID.uuidString):\(key.dateToken):\(snapshot.scoreEvents[index].eventType.rawValue)"
            }
        }
        if snapshot.notificationSettings == nil {
            var settings = UserNotificationSettings.defaults(userID: snapshot.currentUser.id, groups: snapshot.groups.filter { currentUserGroupIDs.contains($0.id) })
            settings.quietHoursStart = snapshot.notificationPreference.quietHoursStart
            settings.quietHoursEnd = snapshot.notificationPreference.quietHoursEnd
            settings.defaultReminderMinutes = snapshot.notificationPreference.reminderMinutes
            if let groupID = snapshot.notificationPreference.groupID,
               let index = settings.groups.firstIndex(where: { $0.groupID == groupID }) {
                settings.groups[index].personalRemindersEnabled = snapshot.notificationPreference.personalRemindersEnabled
                settings.groups[index].friendActivityMode = snapshot.notificationPreference.friendActivityMode
                settings.groups[index].challengeUpdatesEnabled = snapshot.notificationPreference.challengeUpdatesEnabled
            }
            snapshot.notificationSettings = settings
        }
        if snapshot.roundResults == nil {
            if let previous = snapshot.previousRound, let groupID = primaryGroupID {
                snapshot.roundResults = [.init(
                    id: previous.id, groupID: groupID, challengeID: UUID(), title: previous.title,
                    winnerName: previous.winnerName, topThree: previous.topThree,
                    members: previous.topThree.map { .init(user: $0.user, completionRate: $0.completionPercentage, points: $0.points, longestStreak: $0.longestStreak) },
                    totalCompletions: previous.totalCompletions, personalBest: previous.personalBest, completedAt: .distantPast
                )]
            } else {
                snapshot.roundResults = []
            }
        }
        return snapshot
    }

    private static func migrateToV3(_ source: DemoSnapshot) -> DemoSnapshot {
        var snapshot = source
        snapshot.schemaVersion = 3
        for index in snapshot.submissions.indices where snapshot.submissions[index].clips.isEmpty {
            // Legacy rows keep empty clips; new check-ins require proof clips.
            snapshot.submissions[index].clips = []
        }
        return snapshot
    }

    private static func ensureLedgerBaselines(in snapshot: inout DemoSnapshot) {
        for entry in snapshot.leaderboard {
            guard let challengeID = entry.challengeID else { continue }
            let openingKey = "opening-balance:\(challengeID.uuidString):\(entry.user.id.uuidString)"
            guard !snapshot.scoreEvents.contains(where: { $0.scoringKey == openingKey }) else { continue }
            let existing = snapshot.scoreEvents.filter { $0.challengeID == challengeID && $0.userID == entry.user.id }
            let pointDelta = entry.points - existing.reduce(0) { $0 + $1.points }
            let completedDelta = entry.completedRequirements - existing.reduce(0) { partial, event in
                partial + (event.completionDelta ?? (event.eventType == .requirementCompleted ? 1 : 0))
            }
            guard pointDelta != 0 || completedDelta != 0 else { continue }
            let version = snapshot.challenges.first { $0.id == challengeID }?.scoringVersion ?? 1
            snapshot.scoreEvents.append(.init(
                id: UUID(), challengeID: challengeID, userID: entry.user.id, submissionID: nil,
                eventType: .adjustment, points: pointDelta, reason: "Migrated opening balance",
                scoringVersion: version, createdAt: entry.finalScoreAchievedAt,
                requirementDate: nil, scoringKey: openingKey, completionDelta: completedDelta
            ))
        }
    }
}

enum ChallengeFactory {
    static func makeChallenge(from proposal: ChallengeProposal, createdAt: Date, id: UUID = UUID()) -> RoundChallenge {
        RoundChallenge(
            id: id,
            groupID: proposal.groupID,
            proposalID: proposal.id,
            title: proposal.title,
            activityType: proposal.activityType,
            measurementType: proposal.measurementType,
            minimumQuantity: proposal.minimumQuantity,
            frequencyType: proposal.frequencyType,
            scheduledWeekdays: proposal.scheduledWeekdays,
            timesPerWeek: nil,
            startDate: proposal.proposedStartDate,
            endDate: endDate(for: proposal),
            challengeTimezone: proposal.challengeTimezone,
            dailyDeadlineMinutes: proposal.dailyDeadlineMinutes,
            recoveryDayAllowance: proposal.recoveryDayAllowance,
            status: .scheduled,
            scoringVersion: 1,
            createdAt: createdAt
        )
    }

    static func makeChallenge(
        groupID: UUID,
        title: String,
        activityType: String,
        measurementType: MeasurementType,
        minimumQuantity: Double,
        frequencyType: FrequencyType,
        scheduledWeekdays: Set<Int>,
        durationDays: Int,
        startDate: Date,
        challengeTimezone: String,
        dailyDeadlineMinutes: Int,
        recoveryDayAllowance: Int,
        createdAt: Date,
        proposalID: UUID? = nil,
        id: UUID = UUID()
    ) -> RoundChallenge {
        let end = endDate(
            startDate: startDate,
            durationDays: durationDays,
            timezoneIdentifier: challengeTimezone
        )
        return RoundChallenge(
            id: id,
            groupID: groupID,
            proposalID: proposalID,
            title: title,
            activityType: activityType,
            measurementType: measurementType,
            minimumQuantity: minimumQuantity,
            frequencyType: frequencyType,
            scheduledWeekdays: scheduledWeekdays,
            timesPerWeek: nil,
            startDate: startDate,
            endDate: end,
            challengeTimezone: challengeTimezone,
            dailyDeadlineMinutes: dailyDeadlineMinutes,
            recoveryDayAllowance: recoveryDayAllowance,
            status: .scheduled,
            scoringVersion: 1,
            createdAt: createdAt
        )
    }

    static func endDate(for proposal: ChallengeProposal) -> Date {
        endDate(startDate: proposal.proposedStartDate, durationDays: proposal.durationDays, timezoneIdentifier: proposal.challengeTimezone)
    }

    static func endDate(startDate: Date, durationDays: Int, timezoneIdentifier: String) -> Date {
        guard let timezone = TimeZone(identifier: timezoneIdentifier) else { return startDate }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        return calendar.date(byAdding: .day, value: durationDays - 1, to: startDate) ?? startDate
    }

    static func seedLeaderboardEntries(for challenge: RoundChallenge, in snapshot: inout DemoSnapshot, at now: Date) {
        let memberIDs = snapshot.memberships
            .filter { $0.groupID == challenge.groupID && $0.status == .active }
            .map(\.userID)
        let scheduledCount = ScheduleEngine.scheduledDates(for: challenge).count
        for userID in memberIDs {
            guard let user = snapshot.users.first(where: { $0.id == userID }) else { continue }
            let alreadyExists = snapshot.leaderboard.contains {
                $0.user.id == userID && $0.challengeID == challenge.id
            }
            guard !alreadyExists else { continue }
            snapshot.leaderboard.append(
                LeaderboardEntry(
                    user: user,
                    points: 0,
                    completedRequirements: 0,
                    scheduledRequirements: scheduledCount,
                    currentStreak: 0,
                    longestStreak: 0,
                    finalScoreAchievedAt: now,
                    previousRank: nil,
                    groupID: challenge.groupID,
                    challengeID: challenge.id
                )
            )
        }
    }
}
