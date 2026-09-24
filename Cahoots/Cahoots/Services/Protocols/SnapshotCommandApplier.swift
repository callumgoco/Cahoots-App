import Foundation

enum RepositoryCommand: Sendable {
    case createGroup(name: String, emoji: String, memberLimit: Int)
    case joinGroup(code: String)
    case createProposal(groupID: UUID, draft: ProposalDraft)
    case startChallenge(groupID: UUID, draft: ProposalDraft)
    case castVote(proposalID: UUID, choice: VoteChoice)
    case useRecoveryDay(challengeID: UUID)
    case updateProfile(displayName: String?, appearance: AppearancePreference?, showsExactTotals: Bool?)
    case updateNotificationSettings(UserNotificationSettings)
    case updateGroup(id: UUID, name: String, emoji: String, memberLimit: Int)
    case setRole(groupID: UUID, userID: UUID, role: GroupRole)
    case transferOwnership(groupID: UUID, to: UUID)
    case removeMember(groupID: UUID, userID: UUID)
    case leaveGroup(UUID)
    case deleteGroup(UUID)
    case revokeInvites(groupID: UUID)
    case regenerateInvite(groupID: UUID)
    case block(UUID)
    case unblock(UUID)
    case report(userID: UUID, groupID: UUID, reason: String)
    case deleteAccount
}

/// Applies repository commands to a local snapshot (demo mode parity with live RPCs).
enum SnapshotCommandApplier {
    static func apply(_ command: RepositoryCommand, to snapshot: DemoSnapshot, now: Date = .now) throws -> (DemoSnapshot, GroupInvite?) {
        var snapshot = snapshot
        var invite: GroupInvite?

        switch command {
        case .createGroup(let name, let emoji, let memberLimit):
            let cleanName = TextSanitizer.clean(name, maximumLength: 36)
            guard cleanName.count >= 2 else { throw RepositoryError.server("Choose a valid group name.") }
            let group = CahootsGroup(
                id: UUID(), name: cleanName, emoji: emoji.isEmpty ? "⚡️" : String(emoji.prefix(2)),
                ownerID: snapshot.currentUser.id, memberLimit: min(20, max(2, memberLimit)),
                createdAt: now, updatedAt: now, archivedAt: nil
            )
            let newInvite = GroupInvite(
                id: UUID(), groupID: group.id, code: inviteCode(), createdBy: snapshot.currentUser.id,
                expiresAt: now.addingTimeInterval(14 * 86_400), maximumUses: group.memberLimit, useCount: 1, revokedAt: nil
            )
            snapshot.groups.append(group)
            snapshot.memberships.append(.init(
                id: UUID(), groupID: group.id, userID: snapshot.currentUser.id, role: .owner,
                status: .active, joinedAt: now, leftAt: nil, notificationLevel: .immediate
            ))
            snapshot.invites.append(newInvite)
            snapshot.activity.insert(.init(
                id: UUID(), groupID: group.id, actorID: snapshot.currentUser.id,
                actorName: snapshot.currentUser.displayName, eventType: .memberJoined,
                message: "You created \(group.name).", createdAt: now
            ), at: 0)
            invite = newInvite

        case .joinGroup(let rawCode):
            let code = rawCode.uppercased().filter { $0.isLetter || $0.isNumber }
            guard code.count == 6 else { throw RepositoryError.server("Enter a six-character invitation code.") }
            guard let existing = snapshot.invites.first(where: { $0.code == code }) else {
                throw RepositoryError.server("That invitation code was not found.")
            }
            guard let group = snapshot.groups.first(where: { $0.id == existing.groupID }) else {
                throw RepositoryError.server("This group was deleted.")
            }
            if snapshot.blockedUsers.contains(where: { $0.blockerID == snapshot.currentUser.id && $0.blockedUserID == existing.createdBy }) {
                throw RepositoryError.server("This invitation is unavailable.")
            }
            if snapshot.memberships.contains(where: { $0.groupID == group.id && $0.userID == snapshot.currentUser.id && $0.status == .removed }) {
                throw RepositoryError.server("You no longer have access to this group.")
            }
            if snapshot.memberships.contains(where: { $0.groupID == group.id && $0.userID == snapshot.currentUser.id && $0.status == .active }) {
                throw RepositoryError.server("You are already a member of this group.")
            }
            let memberCount = snapshot.memberships.filter { $0.groupID == group.id && $0.status == .active }.count
            switch InviteEngine.validation(invite: existing, memberCount: memberCount) {
            case .expired: throw RepositoryError.server("This invitation has expired.")
            case .groupFull: throw RepositoryError.server("This group is full.")
            case .valid: break
            }
            snapshot.memberships.append(.init(
                id: UUID(), groupID: group.id, userID: snapshot.currentUser.id, role: .member,
                status: .active, joinedAt: now, leftAt: nil, notificationLevel: .immediate
            ))
            if let index = snapshot.invites.firstIndex(where: { $0.id == existing.id }) {
                snapshot.invites[index].useCount += 1
            }

        case .createProposal(let groupID, let draft):
            guard let group = snapshot.groups.first(where: { $0.id == groupID }) else {
                throw RepositoryError.server("Group not found.")
            }
            try validateChallengeDraft(draft, snapshot: snapshot, group: group, now: now)
            let title = TextSanitizer.clean(draft.title, maximumLength: 52)
            let memberIDs = Set(snapshot.memberships.filter { $0.groupID == groupID && $0.status == .active }.map(\.userID))
            let proposal = ChallengeProposal(
                id: UUID(), groupID: group.id, proposedBy: snapshot.currentUser.id, title: title,
                activityType: TextSanitizer.clean(draft.activityName), measurementType: draft.measurementType,
                minimumQuantity: draft.minimumQuantity, frequencyType: draft.frequencyType,
                scheduledWeekdays: draft.scheduledWeekdays, durationDays: draft.durationDays,
                proposedStartDate: draft.startDate, challengeTimezone: draft.timezone,
                dailyDeadlineMinutes: draft.deadlineMinutes, recoveryDayAllowance: draft.recoveryDays,
                votingStartsAt: now, votingEndsAt: now.addingTimeInterval(48 * 3_600),
                eligibleVoterIDs: memberIDs, status: .voting, createdAt: now
            )
            snapshot.proposals.append(proposal)
            snapshot.activity.insert(.init(
                id: UUID(), groupID: group.id, actorID: snapshot.currentUser.id,
                actorName: snapshot.currentUser.displayName, eventType: .proposal,
                message: "You proposed \(title).", createdAt: now
            ), at: 0)

        case .startChallenge(let groupID, let draft):
            guard let group = snapshot.groups.first(where: { $0.id == groupID }) else {
                throw RepositoryError.server("Group not found.")
            }
            try validateChallengeDraft(draft, snapshot: snapshot, group: group, now: now)
            let title = TextSanitizer.clean(draft.title, maximumLength: 52)
            let challenge = ChallengeFactory.makeChallenge(
                groupID: group.id, title: title,
                activityType: TextSanitizer.clean(draft.activityName),
                measurementType: draft.measurementType, minimumQuantity: draft.minimumQuantity,
                frequencyType: draft.frequencyType, scheduledWeekdays: draft.scheduledWeekdays,
                durationDays: draft.durationDays, startDate: draft.startDate,
                challengeTimezone: draft.timezone, dailyDeadlineMinutes: draft.deadlineMinutes,
                recoveryDayAllowance: draft.recoveryDays, createdAt: now
            )
            snapshot.challenges.append(challenge)
            ChallengeFactory.seedLeaderboardEntries(for: challenge, in: &snapshot, at: now)
            snapshot.activity.insert(.init(
                id: UUID(), groupID: group.id, actorID: snapshot.currentUser.id,
                actorName: snapshot.currentUser.displayName, eventType: .challengeStarted,
                message: "You started \(title).", createdAt: now
            ), at: 0)

        case .castVote(let proposalID, let choice):
            guard let proposal = snapshot.proposals.first(where: { $0.id == proposalID }),
                  proposal.status == .voting, proposal.votingEndsAt > now,
                  proposal.eligibleVoterIDs.contains(snapshot.currentUser.id) else {
                throw RepositoryError.server("This vote is not available.")
            }
            VotingEngine.upsert(choice: choice, userID: snapshot.currentUser.id, proposalID: proposalID, votes: &snapshot.votes, now: now)

        case .useRecoveryDay(let challengeID):
            guard let challenge = snapshot.challenges.first(where: { $0.id == challengeID && $0.status == .active }) else {
                throw RepositoryError.server("This round is no longer available.")
            }
            let used = snapshot.recoveryDays.filter { $0.challengeID == challengeID && $0.userID == snapshot.currentUser.id }.count
            guard used < challenge.recoveryDayAllowance else {
                throw RepositoryError.server("No recovery days remaining.")
            }
            let requirementDate = ScheduleEngine.requirementDay(for: now, challenge: challenge) ?? now
            snapshot.recoveryDays.append(.init(
                id: UUID(), challengeID: challengeID, userID: snapshot.currentUser.id,
                requirementDate: requirementDate, createdAt: now
            ))
            snapshot.activity.insert(.init(
                id: UUID(), groupID: challenge.groupID, actorID: snapshot.currentUser.id,
                actorName: snapshot.currentUser.displayName, eventType: .recovery,
                message: "You used a recovery day.", createdAt: now
            ), at: 0)

        case .updateProfile(let displayName, let appearance, let showsExactTotals):
            if let displayName {
                let clean = TextSanitizer.clean(displayName, maximumLength: 40)
                guard clean.count >= 2 else { throw RepositoryError.server("Choose a display name between 2 and 40 characters.") }
                snapshot.currentUser.displayName = clean
            }
            if let appearance { snapshot.appearance = appearance }
            if let showsExactTotals { snapshot.currentUser.showsExactTotals = showsExactTotals }
            snapshot.currentUser.updatedAt = now
            if let index = snapshot.users.firstIndex(where: { $0.id == snapshot.currentUser.id }) {
                snapshot.users[index] = snapshot.currentUser
            }

        case .updateNotificationSettings(let settings):
            snapshot.notificationSettings = settings

        case .updateGroup(let id, let name, let emoji, let memberLimit):
            guard let index = snapshot.groups.firstIndex(where: { $0.id == id }) else {
                throw RepositoryError.server("Group not found.")
            }
            let cleanName = TextSanitizer.clean(name, maximumLength: 36)
            let activeCount = snapshot.memberships.filter { $0.groupID == id && $0.status == .active }.count
            guard cleanName.count >= 2, memberLimit >= activeCount, (2...20).contains(memberLimit) else {
                throw RepositoryError.server("Choose a valid name and member limit.")
            }
            snapshot.groups[index].name = cleanName
            snapshot.groups[index].emoji = emoji.isEmpty ? "⚡️" : String(emoji.prefix(2))
            snapshot.groups[index].memberLimit = memberLimit
            snapshot.groups[index].updatedAt = now

        case .setRole(let groupID, let userID, let role):
            guard role != .owner,
                  let index = snapshot.memberships.firstIndex(where: { $0.groupID == groupID && $0.userID == userID && $0.status == .active }),
                  snapshot.memberships[index].role != .owner else {
                throw RepositoryError.server("You cannot change this member's role.")
            }
            snapshot.memberships[index].role = role

        case .transferOwnership(let groupID, let newOwnerID):
            guard let oldOwnerIndex = snapshot.memberships.firstIndex(where: { $0.groupID == groupID && $0.userID == snapshot.currentUser.id && $0.status == .active }),
                  let newOwnerIndex = snapshot.memberships.firstIndex(where: { $0.groupID == groupID && $0.userID == newOwnerID && $0.status == .active }),
                  let groupIndex = snapshot.groups.firstIndex(where: { $0.id == groupID }) else {
                throw RepositoryError.server("Ownership transfer is not available.")
            }
            snapshot.memberships[oldOwnerIndex].role = .admin
            snapshot.memberships[newOwnerIndex].role = .owner
            snapshot.groups[groupIndex].ownerID = newOwnerID
            snapshot.groups[groupIndex].updatedAt = now

        case .removeMember(let groupID, let userID):
            guard userID != snapshot.groups.first(where: { $0.id == groupID })?.ownerID,
                  let index = snapshot.memberships.firstIndex(where: { $0.groupID == groupID && $0.userID == userID && $0.status == .active }) else {
                throw RepositoryError.server("You cannot remove this member.")
            }
            snapshot.memberships[index].status = .removed
            snapshot.memberships[index].leftAt = now

        case .leaveGroup(let groupID):
            guard let index = snapshot.memberships.firstIndex(where: { $0.groupID == groupID && $0.userID == snapshot.currentUser.id && $0.status == .active }) else {
                throw RepositoryError.server("You are not a member of this group.")
            }
            let membership = snapshot.memberships[index]
            let memberCount = snapshot.memberships.filter { $0.groupID == groupID && $0.status == .active }.count
            guard MembershipRules.canLeave(role: membership.role, activeMemberCount: memberCount) else {
                throw RepositoryError.server("Transfer ownership before leaving this group.")
            }
            snapshot.memberships[index].status = .left
            snapshot.memberships[index].leftAt = now
            if membership.role == .owner && memberCount == 1,
               let groupIndex = snapshot.groups.firstIndex(where: { $0.id == groupID }) {
                snapshot.groups[groupIndex].archivedAt = now
                for inviteIndex in snapshot.invites.indices where snapshot.invites[inviteIndex].groupID == groupID && snapshot.invites[inviteIndex].revokedAt == nil {
                    snapshot.invites[inviteIndex].revokedAt = now
                }
            }

        case .deleteGroup(let groupID):
            guard let membership = snapshot.memberships.first(where: {
                $0.groupID == groupID && $0.userID == snapshot.currentUser.id && $0.status == .active
            }), GroupPermissionRules.canDelete(membership.role) else {
                throw RepositoryError.server("You do not have permission to do that.")
            }
            let challengeIDs = Set(snapshot.challenges.filter { $0.groupID == groupID }.map(\.id))
            let proposalIDs = Set(snapshot.proposals.filter { $0.groupID == groupID }.map(\.id))
            let removedClientIDs = Set(snapshot.submissions.filter { challengeIDs.contains($0.challengeID) }.map(\.clientGeneratedID))
            snapshot.groups.removeAll { $0.id == groupID }
            snapshot.memberships.removeAll { $0.groupID == groupID }
            snapshot.invites.removeAll { $0.groupID == groupID }
            snapshot.challenges.removeAll { $0.groupID == groupID }
            snapshot.proposals.removeAll { $0.groupID == groupID }
            snapshot.votes.removeAll { proposalIDs.contains($0.proposalID) }
            snapshot.submissions.removeAll { challengeIDs.contains($0.challengeID) }
            snapshot.scoreEvents.removeAll { challengeIDs.contains($0.challengeID) }
            snapshot.recoveryDays.removeAll { challengeIDs.contains($0.challengeID) }
            snapshot.leaderboard.removeAll { $0.groupID == groupID }
            snapshot.allTimeLeaderboard.removeAll { $0.groupID == groupID }
            snapshot.activity.removeAll { $0.groupID == groupID }
            snapshot.reports.removeAll { $0.groupID == groupID }
            snapshot.pendingOperations.removeAll { removedClientIDs.contains($0.clientGeneratedID) }
            if var settings = snapshot.notificationSettings {
                settings.groups.removeAll { $0.groupID == groupID }
                snapshot.notificationSettings = settings
            }
            if snapshot.notificationPreference.groupID == groupID {
                snapshot.notificationPreference.groupID = nil
            }
            if var results = snapshot.roundResults {
                results.removeAll { $0.groupID == groupID }
                snapshot.roundResults = results
            }

        case .revokeInvites(let groupID):
            for index in snapshot.invites.indices where snapshot.invites[index].groupID == groupID && snapshot.invites[index].revokedAt == nil {
                snapshot.invites[index].revokedAt = now
            }

        case .regenerateInvite(let groupID):
            guard let group = snapshot.groups.first(where: { $0.id == groupID }) else {
                throw RepositoryError.server("Group not found.")
            }
            for index in snapshot.invites.indices where snapshot.invites[index].groupID == groupID && snapshot.invites[index].revokedAt == nil {
                snapshot.invites[index].revokedAt = now
            }
            let newInvite = GroupInvite(
                id: UUID(), groupID: group.id, code: inviteCode(), createdBy: snapshot.currentUser.id,
                expiresAt: now.addingTimeInterval(14 * 86_400), maximumUses: group.memberLimit, useCount: 0, revokedAt: nil
            )
            snapshot.invites.append(newInvite)
            invite = newInvite

        case .block(let userID):
            if !snapshot.blockedUsers.contains(where: { $0.blockerID == snapshot.currentUser.id && $0.blockedUserID == userID }) {
                snapshot.blockedUsers.append(.init(id: UUID(), blockerID: snapshot.currentUser.id, blockedUserID: userID, createdAt: now))
            }

        case .unblock(let userID):
            snapshot.blockedUsers.removeAll {
                $0.blockerID == snapshot.currentUser.id && $0.blockedUserID == userID
            }

        case .report(let userID, let groupID, let reason):
            let cleanReason = TextSanitizer.clean(reason, maximumLength: 280)
            guard cleanReason.count >= 3 else { throw RepositoryError.server("Choose a report reason before submitting.") }
            snapshot.reports.append(.init(
                id: UUID(), reporterID: snapshot.currentUser.id, reportedUserID: userID,
                groupID: groupID, reason: cleanReason, createdAt: now
            ))

        case .deleteAccount:
            snapshot.currentUser.deletedAt = now
            snapshot.groups.removeAll()
            snapshot.memberships.removeAll()
        }

        return (snapshot, invite)
    }

    private static func validateChallengeDraft(_ draft: ProposalDraft, snapshot: DemoSnapshot, group: CahootsGroup, now: Date) throws {
        if snapshot.proposals.contains(where: { $0.groupID == group.id && $0.status == .voting }) {
            throw RepositoryError.server("This group already has a vote in progress.")
        }
        if snapshot.challenges.contains(where: { $0.groupID == group.id && $0.status == .scheduled }) {
            throw RepositoryError.server("This group already has its next round scheduled.")
        }
        if ScheduleEngine.firstCheckInAlreadyClosed(
            startDate: draft.startDate,
            deadlineMinutes: draft.deadlineMinutes,
            timeZoneIdentifier: draft.timezone,
            frequencyType: draft.frequencyType,
            scheduledWeekdays: draft.scheduledWeekdays,
            now: now
        ) {
            throw RepositoryError.server(ScheduleEngine.firstCheckInClosedMessage)
        }
        let title = TextSanitizer.clean(draft.title, maximumLength: 52)
        guard !title.isEmpty, draft.minimumQuantity > 0, !draft.scheduledWeekdays.isEmpty,
              (7...90).contains(draft.durationDays), (0...4).contains(draft.recoveryDays) else {
            throw RepositoryError.server("Check the target, schedule, duration, and recovery allowance.")
        }
    }

    private static func inviteCode() -> String {
        let characters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).compactMap { _ in characters.randomElement() })
    }
}
