import Foundation

extension AppStore {
    func createGroup(name: String, emoji: String, memberLimit: Int) async -> GroupInvite? {
        guard requireConnection() else { return nil }
        guard await applyCommand(.createGroup(name: name, emoji: emoji, memberLimit: memberLimit)) else { return nil }
        if let group = activeGroups.first {
            ensureNotificationSettings(for: group.id)
            setActiveGroup(group.id)
        }
        await rebuildNotificationPlan()
        return snapshot?.invites.filter { $0.revokedAt == nil }.max(by: { $0.expiresAt < $1.expiresAt })
    }

    func finishGroupCreation() {
        loadState = currentGroup == nil ? .empty : .loaded
    }

    func joinGroup(code rawCode: String) async -> String? {
        guard requireConnection() else { return String(localized: "Connect to the internet to join a group.") }
        let code = rawCode.uppercased().filter { $0.isLetter || $0.isNumber }
        guard code.count == 6 else { return String(localized: "Enter a six-character invitation code.") }
        do {
            if let updated = try await environment.repository.perform(.joinGroup(code: code)) {
                snapshot = SnapshotMigrator.migrate(updated)
            } else {
                await load(reset: false)
            }
            if let group = activeGroups.first {
                ensureNotificationSettings(for: group.id)
                setActiveGroup(group.id)
            }
            loadState = .loaded
            await rebuildNotificationPlan()
            if let proposal = currentProposal,
               proposal.eligibleVoterIDs.contains(snapshot?.currentUser.id ?? UUID()),
               !(snapshot?.votes.contains { $0.proposalID == proposal.id && $0.userID == snapshot?.currentUser.id } ?? false) {
                noticeBanner = String(localized: "Welcome aboard — this crew has an open vote.")
                presentVote(groupID: proposal.groupID, proposalID: proposal.id)
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func selectGroup(_ groupID: UUID) {
        guard activeGroups.contains(where: { $0.id == groupID }) else { return }
        setActiveGroup(groupID)
        selectedTab = min(selectedTab, 3)
        // Check-in window messaging is crew-scoped; drop a stale closed-window banner when switching.
        if errorBanner == CheckInSubmissionRules.closedWindowMessage {
            errorBanner = nil
        }
        Task { await rebuildNotificationPlan() }
    }

    func createProposal(from draft: ProposalDraft) async -> Bool {
        guard requireConnection(), let snapshot, let group = currentGroup else { return false }
        let activeCount = snapshot.memberships.filter { $0.groupID == group.id && $0.status == .active }.count
        guard activeCount >= 2 else {
            errorBanner = VotingWindowCopy.soloVoteDisabledHint
            return false
        }
        guard validateChallengeDraft(draft, snapshot: snapshot, group: group) else { return false }
        guard await applyCommand(.createProposal(groupID: group.id, draft: draft)) else { return false }
        // Proposer auto-accepts so the vote reflects their intent; they can still change it.
        await castVote(.accept)
        presentVote()
        return true
    }

    func startChallenge(from draft: ProposalDraft) async -> Bool {
        guard requireConnection(), let snapshot, let group = currentGroup else { return false }
        guard validateChallengeDraft(draft, snapshot: snapshot, group: group) else { return false }
        let title = TextSanitizer.clean(draft.title, maximumLength: 52)
        guard await applyCommand(.startChallenge(groupID: group.id, draft: draft)) else { return false }
        await reconcileAndPersist()
        await rebuildNotificationPlan()
        noticeBanner = String(localized: "\(title) is ready.")
        return true
    }

    func validateChallengeDraft(_ draft: ProposalDraft, snapshot: DemoSnapshot, group: CahootsGroup) -> Bool {
        let hasOpenProposal = snapshot.proposals.contains { $0.groupID == group.id && $0.status == .voting }
        let hasScheduledSuccessor = snapshot.challenges.contains { $0.groupID == group.id && $0.status == .scheduled }
        if hasOpenProposal {
            errorBanner = String(localized: "This group already has a vote in progress.")
            return false
        }
        if hasScheduledSuccessor {
            errorBanner = String(localized: "This group already has its next round scheduled.")
            return false
        }
        if let active = snapshot.challenges.first(where: { $0.groupID == group.id && $0.status == .active }),
           let calendar = ScheduleEngine.calendar(for: active),
           let earliest = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: active.endDate)),
           draft.startDate < earliest {
            errorBanner = String(localized: "The next round must start after \(active.title) ends.")
            return false
        }
        let title = TextSanitizer.clean(draft.title, maximumLength: 52)
        guard !title.isEmpty, draft.minimumQuantity > 0, !draft.scheduledWeekdays.isEmpty,
              (7...90).contains(draft.durationDays), (0...4).contains(draft.recoveryDays) else {
            errorBanner = String(localized: "Check the target, schedule, duration, and recovery allowance.")
            return false
        }
        return true
    }

    func removeMember(_ userID: UUID) async {
        guard requireConnection(), let groupID = currentGroup?.id,
              let actorRole = currentMembership?.role,
              userID != currentGroup?.ownerID,
              let target = snapshot?.memberships.first(where: { $0.groupID == groupID && $0.userID == userID && $0.status == .active }) else { return }
        guard GroupPermissionRules.canRemove(actor: actorRole, target: target.role) else {
            errorBanner = String(localized: "You do not have permission to remove this member.")
            return
        }
        if await applyCommand(.removeMember(groupID: groupID, userID: userID)) {
            noticeBanner = String(localized: "Member removed from the group.")
        }
    }

    func transferOwnership(to userID: UUID) async {
        guard requireConnection(), let group = currentGroup,
              currentMembership.map({ GroupPermissionRules.canChangeRoles($0.role) }) == true,
              userID != snapshot?.currentUser.id else { return }
        if await applyCommand(.transferOwnership(groupID: group.id, to: userID)) {
            noticeBanner = String(localized: "Ownership transferred.")
        }
    }

    func setRole(_ role: GroupRole, for userID: UUID) async {
        guard requireConnection(), role != .owner, let group = currentGroup,
              currentMembership.map({ GroupPermissionRules.canChangeRoles($0.role) }) == true,
              userID != snapshot?.currentUser.id else { return }
        if await applyCommand(.setRole(groupID: group.id, userID: userID, role: role)) {
            noticeBanner = role == .admin
                ? String(localized: "Member promoted to admin.")
                : String(localized: "Admin changed to member.")
        }
    }

    func updateCurrentGroup(name: String, emoji: String, memberLimit: Int) async -> Bool {
        guard requireConnection(), let group = currentGroup,
              currentMembership.map({ GroupPermissionRules.canEditSettings($0.role) }) == true else { return false }
        let cleanName = TextSanitizer.clean(name, maximumLength: 36)
        let activeCount = snapshot?.memberships.filter { $0.groupID == group.id && $0.status == .active }.count ?? 0
        guard cleanName.count >= 2, memberLimit >= activeCount, (2...20).contains(memberLimit) else {
            errorBanner = String(localized: "Choose a valid name and a member limit no lower than the current member count.")
            return false
        }
        let saved = await applyCommand(.updateGroup(id: group.id, name: cleanName, emoji: emoji, memberLimit: memberLimit))
        if saved { noticeBanner = String(localized: "Group settings updated.") }
        return saved
    }

    func revokeCurrentInvite() async {
        guard requireConnection(), let groupID = currentGroup?.id,
              currentMembership.map({ GroupPermissionRules.canManageInvites($0.role) }) == true else { return }
        if await applyCommand(.revokeInvites(groupID: groupID)) {
            noticeBanner = String(localized: "Invitation revoked.")
        }
    }

    func regenerateCurrentInvite() async -> GroupInvite? {
        guard requireConnection(), let group = currentGroup,
              currentMembership.map({ GroupPermissionRules.canManageInvites($0.role) }) == true else { return nil }
        guard await applyCommand(.regenerateInvite(groupID: group.id)) else { return nil }
        noticeBanner = String(localized: "A new invitation is ready.")
        return snapshot?.invites.filter { $0.groupID == group.id && $0.revokedAt == nil }.max(by: { $0.expiresAt < $1.expiresAt })
    }

    func leaveCurrentGroup() async -> Bool {
        guard requireConnection(), let group = currentGroup,
              let membership = snapshot?.memberships.first(where: { $0.groupID == group.id && $0.userID == snapshot?.currentUser.id && $0.status == .active }) else { return false }
        let memberCount = snapshot?.memberships.filter { $0.groupID == group.id && $0.status == .active }.count ?? 0
        guard MembershipRules.canLeave(role: membership.role, activeMemberCount: memberCount) else {
            errorBanner = String(localized: "Transfer ownership before leaving this group.")
            return false
        }
        guard await applyCommand(.leaveGroup(group.id)) else { return false }
        setActiveGroup(activeGroups.first(where: { $0.id != group.id })?.id)
        loadState = currentGroup == nil ? .empty : .loaded
        noticeBanner = String(localized: "You left the group.")
        await rebuildNotificationPlan()
        return true
    }

    func deleteCurrentGroup() async -> Bool {
        guard requireConnection(), let group = currentGroup,
              currentMembership.map({ GroupPermissionRules.canDelete($0.role) }) == true else {
            errorBanner = String(localized: "Only the group owner can delete this group.")
            return false
        }
        guard await applyCommand(.deleteGroup(group.id)) else { return false }
        setActiveGroup(activeGroups.first(where: { $0.id != group.id })?.id)
        loadState = currentGroup == nil ? .empty : .loaded
        noticeBanner = String(localized: "Group deleted.")
        await rebuildNotificationPlan()
        return true
    }

    func block(_ user: CahootsUser) async {
        if await applyCommand(.block(user.id)) {
            noticeBanner = String(localized: "Member blocked. Their activity is now hidden.")
        }
    }

    func unblock(userID: UUID) async {
        if await applyCommand(.unblock(userID)) {
            noticeBanner = String(localized: "Member unblocked.")
        }
    }

    func report(_ user: CahootsUser, reason: String) async {
        guard requireConnection(), let groupID = currentGroup?.id else { return }
        let cleanReason = TextSanitizer.clean(reason, maximumLength: 280)
        guard cleanReason.count >= 3 else {
            errorBanner = String(localized: "Choose a report reason before submitting.")
            return
        }
        if await applyCommand(.report(userID: user.id, groupID: groupID, reason: cleanReason)) {
            noticeBanner = String(localized: "Report submitted. Thank you for letting us know.")
        }
    }

    func setActiveGroup(_ groupID: UUID?) {
        activeGroupID = groupID
        if let groupID {
            UserDefaults.standard.set(groupID.uuidString, forKey: AppDefaults.activeGroupID)
        } else {
            UserDefaults.standard.removeObject(forKey: AppDefaults.activeGroupID)
        }
    }

    func ensureNotificationSettings(for groupID: UUID) {
        guard var snapshot else { return }
        var settings = snapshot.notificationSettings ?? UserNotificationSettings.defaults(userID: snapshot.currentUser.id, groups: activeGroups)
        if !settings.groups.contains(where: { $0.groupID == groupID }) {
            settings.groups.append(.defaults(groupID: groupID))
        }
        snapshot.notificationSettings = settings
        self.snapshot = snapshot
    }

    static func inviteCode() -> String {
        let characters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).compactMap { _ in characters.randomElement() })
    }
}
