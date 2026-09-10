import Foundation

extension AppStore {
    var mode: AppMode { environment.repository.mode }
    var isOffline: Bool { !environment.network.isConnected }
    var currentUser: CahootsUser? { snapshot?.currentUser }
    var activeGroups: [CahootsGroup] {
        guard let snapshot else { return [] }
        let memberships = snapshot.memberships.filter {
            $0.userID == snapshot.currentUser.id && $0.status == .active
        }.sorted { $0.joinedAt > $1.joinedAt }
        let groupsByID = Dictionary(uniqueKeysWithValues: snapshot.groups.map { ($0.id, $0) })
        return memberships.compactMap { groupsByID[$0.groupID] }.filter { $0.archivedAt == nil }
    }
    var currentGroup: CahootsGroup? {
        activeGroups.first { $0.id == activeGroupID } ?? activeGroups.first
    }
    var currentChallenge: CahootsChallenge? {
        guard let groupID = currentGroup?.id else { return nil }
        return snapshot?.challenges
            .filter { $0.groupID == groupID && ($0.status == .active || $0.status == .scheduled) }
            .sorted {
                if $0.status != $1.status { return $0.status == .active }
                return $0.startDate < $1.startDate
            }.first
    }
    var currentProposal: ChallengeProposal? {
        guard let groupID = currentGroup?.id else { return nil }
        return snapshot?.proposals.first { $0.groupID == groupID && $0.status == .voting }
    }

    /// Open votes across every active group where the current user still needs to vote.
    var pendingVoteCount: Int {
        guard let snapshot else { return 0 }
        let activeGroupIDs = Set(activeGroups.map(\.id))
        let userID = snapshot.currentUser.id
        return snapshot.proposals.filter { proposal in
            proposal.status == .voting
                && activeGroupIDs.contains(proposal.groupID)
                && proposal.eligibleVoterIDs.contains(userID)
                && !snapshot.votes.contains { $0.proposalID == proposal.id && $0.userID == userID }
        }.count
    }

    var latestFailedProposal: ChallengeProposal? {
        guard let groupID = currentGroup?.id else { return nil }
        return snapshot?.proposals.filter { $0.groupID == groupID && $0.status == .failed }.max { $0.createdAt < $1.createdAt }
    }
    var groupMembers: [CahootsUser] {
        guard let snapshot, let groupID = currentGroup?.id else { return [] }
        let ids = Set(snapshot.memberships.filter { $0.groupID == groupID && $0.status == .active }.map(\.userID))
        return snapshot.users.filter { ids.contains($0.id) }
    }
    var currentMembership: GroupMembership? {
        guard let snapshot, let groupID = currentGroup?.id else { return nil }
        return snapshot.memberships.first { $0.groupID == groupID && $0.userID == snapshot.currentUser.id && $0.status == .active }
    }
    var currentLeaderboard: [LeaderboardEntry] {
        guard let snapshot, let groupID = currentGroup?.id else { return [] }
        let challengeID = currentChallenge?.id
        var entries = snapshot.leaderboard.filter {
            ($0.groupID == groupID || $0.groupID == nil) && (challengeID == nil || $0.challengeID == challengeID || $0.challengeID == nil)
        }
        if let challenge = currentChallenge,
           let currentIndex = entries.firstIndex(where: { $0.user.id == snapshot.currentUser.id }) {
            var provisionalByRequirement: [RequirementKey: Int] = [:]
            for submission in snapshot.submissions where submission.challengeID == challenge.id && submission.userID == snapshot.currentUser.id && (submission.syncState == .waiting || submission.syncState == .failed) {
                guard let key = RequirementKey(challenge: challenge, userID: submission.userID, date: submission.requirementDate) else { continue }
                let points = ScoringEngine.points(completedQuantity: submission.quantity, minimumQuantity: challenge.minimumQuantity)
                provisionalByRequirement[key] = max(provisionalByRequirement[key] ?? 0, points)
            }
            for (key, points) in provisionalByRequirement where points > 0 {
                let acceptedKey = "\(key.challengeID.uuidString):\(key.userID.uuidString):\(key.dateToken):\(ScoreEventType.requirementCompleted.rawValue)"
                guard !snapshot.scoreEvents.contains(where: { $0.scoringKey == acceptedKey }) else { continue }
                entries[currentIndex].points += points
                entries[currentIndex].completedRequirements += 1
            }
        }
        if let challenge = currentChallenge, !canRevealTodayQuantities {
            let now = environment.clock.now
            for index in entries.indices where entries[index].user.id != snapshot.currentUser.id {
                let peerToday = snapshot.submissions.filter {
                    $0.challengeID == challenge.id
                        && $0.userID == entries[index].user.id
                        && $0.syncState != .rejected
                        && ScheduleEngine.isSameRequirementDay($0.requirementDate, now, challenge: challenge)
                }
                let hidden = peerToday.reduce(0) {
                    $0 + CheckInVisibility.todayPointsToHide(
                        submission: $1,
                        challenge: challenge,
                        viewerUserID: snapshot.currentUser.id,
                        canReveal: false
                    )
                }
                if hidden > 0 {
                    entries[index].points = max(0, entries[index].points - hidden)
                }
            }
        }
        return LeaderboardEngine.ranked(entries)
    }
    var allTimeLeaderboard: [LeaderboardEntry] {
        guard let groupID = currentGroup?.id else { return [] }
        return LeaderboardEngine.ranked((snapshot?.allTimeLeaderboard ?? []).filter { $0.groupID == groupID || $0.groupID == nil })
    }
    var currentActivity: [ActivityFeedItem] {
        guard let snapshot, let groupID = currentGroup?.id else { return [] }
        let blocked = Set(snapshot.blockedUsers.filter { $0.blockerID == snapshot.currentUser.id }.map(\.blockedUserID))
        return snapshot.activity.filter { $0.groupID == groupID && !($0.actorID.map(blocked.contains) ?? false) }
    }
    var currentCahootsResults: [CahootsResult] {
        guard let groupID = currentGroup?.id else { return [] }
        return (snapshot?.roundResults ?? []).filter { $0.groupID == groupID }.sorted { $0.completedAt > $1.completedAt }
    }
    var currentPendingOperations: [PendingSyncOperation] {
        guard let snapshot, let groupID = currentGroup?.id else { return [] }
        let challengeIDs = Set(snapshot.challenges.filter { $0.groupID == groupID }.map(\.id))
        let submissionClientIDs = Set(snapshot.submissions.filter { challengeIDs.contains($0.challengeID) }.map(\.clientGeneratedID))
        return snapshot.pendingOperations.filter { submissionClientIDs.contains($0.clientGeneratedID) }
    }
    /// Latest sync failure reason for the current group's pending check-ins, if any.
    var currentPendingSyncError: String? {
        currentPendingOperations.compactMap(\.lastError).first { !$0.isEmpty }
    }
    var hasFailedPendingSync: Bool {
        guard let snapshot else { return false }
        return currentPendingOperations.contains { operation in
            snapshot.submissions.first(where: { $0.clientGeneratedID == operation.clientGeneratedID })?.syncState == .failed
        }
    }
    var currentRejectedSubmissions: [Submission] {
        guard let snapshot, let groupID = currentGroup?.id else { return [] }
        let challengeIDs = Set(snapshot.challenges.filter { $0.groupID == groupID }.map(\.id))
        return snapshot.submissions.filter { challengeIDs.contains($0.challengeID) && $0.syncState == .rejected }
    }
    var currentRank: Int? {
        guard let userID = currentUser?.id else { return nil }
        return currentLeaderboard.firstIndex { $0.user.id == userID }.map { $0 + 1 }
    }
    var hasProvisionalLeaderboardPoints: Bool {
        guard let snapshot, let groupID = currentGroup?.id else { return false }
        let challengeIDs = Set(snapshot.challenges.filter { $0.groupID == groupID }.map(\.id))
        return snapshot.submissions.contains {
            $0.userID == snapshot.currentUser.id && challengeIDs.contains($0.challengeID) &&
            ($0.syncState == .waiting || $0.syncState == .failed)
        }
    }
    var todaySubmission: Submission? {
        guard let snapshot, let challenge = currentChallenge else { return nil }
        return snapshot.submissions.filter {
            $0.challengeID == challenge.id && $0.userID == snapshot.currentUser.id && $0.syncState != .rejected &&
            ScheduleEngine.isSameRequirementDay($0.requirementDate, environment.clock.now, challenge: challenge)
        }.max { $0.quantity < $1.quantity }
    }
    var todayPoints: Int {
        guard let challenge = currentChallenge, let submission = todaySubmission else { return 0 }
        return ScoringEngine.points(completedQuantity: submission.quantity, minimumQuantity: challenge.minimumQuantity)
    }
    var canRevealTodayQuantities: Bool {
        guard let challenge = currentChallenge else { return false }
        let now = environment.clock.now
        let completed = todayPoints > 0
        let deadline = ScheduleEngine.deadline(for: now, challenge: challenge)
        return CheckInVisibility.canRevealToday(
            viewerHasCompleted: completed,
            usedRecovery: recoveryUsedToday,
            now: now,
            deadline: deadline
        )
    }
    /// Today's peer check-ins for the selected group, with quantity/media redacted until unlock.
    var todayPeerCheckIns: [Submission] {
        guard let snapshot, let challenge = currentChallenge else { return [] }
        let now = environment.clock.now
        let blocked = Set(snapshot.blockedUsers.filter { $0.blockerID == snapshot.currentUser.id }.map(\.blockedUserID))
        let reveal = canRevealTodayQuantities
        return snapshot.submissions
            .filter {
                $0.challengeID == challenge.id
                    && $0.userID != snapshot.currentUser.id
                    && $0.syncState != .rejected
                    && !blocked.contains($0.userID)
                    && ScheduleEngine.isSameRequirementDay($0.requirementDate, now, challenge: challenge)
                    && (
                        ScoringEngine.points(completedQuantity: $0.quantity, minimumQuantity: challenge.minimumQuantity) > 0
                        || (!$0.clips.isEmpty && $0.quantity == 0)
                    )
            }
            .map { CheckInVisibility.redacted($0, reveal: reveal) }
            .sorted { $0.submittedAt > $1.submittedAt }
    }
    var recoveryUsedToday: Bool {
        guard let snapshot, let challenge = currentChallenge else { return false }
        return snapshot.recoveryDays.contains {
            $0.challengeID == challenge.id && $0.userID == snapshot.currentUser.id &&
            ScheduleEngine.isSameRequirementDay($0.requirementDate, environment.clock.now, challenge: challenge)
        }
    }
    var remainingRecoveryDays: Int {
        guard let snapshot, let challenge = currentChallenge else { return 0 }
        let used = snapshot.recoveryDays.filter { $0.challengeID == challenge.id && $0.userID == snapshot.currentUser.id }.count
        return max(0, challenge.recoveryDayAllowance - used)
    }

    /// Full-roster today status for the current crew (done / rest / pending). Spoiler-safe.
    var todayMemberStatuses: [TodayMemberStatusEntry] {
        guard let snapshot, let challenge = currentChallenge else { return [] }
        let blocked = Set(snapshot.blockedUsers.filter { $0.blockerID == snapshot.currentUser.id }.map(\.blockedUserID))
        let members = groupMembers.filter { !blocked.contains($0.id) }
        return TodayCrewStatusBuilder.statuses(
            members: members,
            submissions: snapshot.submissions,
            recoveries: snapshot.recoveryDays,
            challenge: challenge,
            now: environment.clock.now,
            currentUserID: snapshot.currentUser.id
        )
    }
    var earliestProposalStartDate: Date {
        let now = environment.clock.now
        guard let active = currentChallenge, active.status == .active,
              let calendar = ScheduleEngine.calendar(for: active) else {
            return Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now
        }
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: active.endDate)) ?? active.endDate
    }
}
