import AuthenticationServices
import BackgroundTasks
import Foundation
import Observation
import OSLog
import UserNotifications

enum LoadState: Equatable {
    case idle, loading, loaded, empty, error(String)
}

enum CheckInLogResult: Equatable, Sendable {
    case saved(points: Int, syncState: SyncState)
    case validationFailed(message: String)
    case persistenceFailed(message: String)
}

enum NotificationAuthorizationState: Equatable, Sendable {
    case undetermined, denied, authorized, provisional
}

@MainActor
@Observable
final class AppStore {
    let environment: AppEnvironment
    private(set) var snapshot: DemoSnapshot?
    private(set) var loadState: LoadState = .idle
    var hasCompletedOnboarding: Bool
    var isSignedIn = false
    var activeGroupID: UUID?
    var selectedTab = 0
    var errorBanner: String?
    var noticeBanner: String?
    var showNotificationPrimer = false
    var showCompletion = false
    var pendingJoinCode: String?
    var pendingLogWorkoutGroupID: UUID?
    var presentWorkoutSession = false
    /// Bumped when a two-clip pending session is saved or cleared so Today refreshes Finish workout.
    private(set) var pendingWorkoutSessionRevision = 0
    var notificationsDenied = false
    private(set) var notificationAuthorizationState: NotificationAuthorizationState = .undetermined
    var sessionRecoveryRequired = false
    private var boundaryTask: Task<Void, Never>?

    init(environment: AppEnvironment) {
        self.environment = environment
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-resetDemo") {
            UserDefaults.standard.removeObject(forKey: "round.onboarding.complete")
            UserDefaults.standard.removeObject(forKey: "round.activeGroupID")
        }
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "round.onboarding.complete")
        activeGroupID = UserDefaults.standard.string(forKey: "round.activeGroupID").flatMap(UUID.init(uuidString:))
    }

    var mode: AppMode { environment.repository.mode }
    var isOffline: Bool { !environment.network.isConnected }
    var currentUser: RoundUser? { snapshot?.currentUser }
    var activeGroups: [RoundGroup] {
        guard let snapshot else { return [] }
        let memberships = snapshot.memberships.filter {
            $0.userID == snapshot.currentUser.id && $0.status == .active
        }.sorted { $0.joinedAt > $1.joinedAt }
        let groupsByID = Dictionary(uniqueKeysWithValues: snapshot.groups.map { ($0.id, $0) })
        return memberships.compactMap { groupsByID[$0.groupID] }.filter { $0.archivedAt == nil }
    }
    var currentGroup: RoundGroup? {
        activeGroups.first { $0.id == activeGroupID } ?? activeGroups.first
    }
    var currentChallenge: RoundChallenge? {
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
    var latestFailedProposal: ChallengeProposal? {
        guard let groupID = currentGroup?.id else { return nil }
        return snapshot?.proposals.filter { $0.groupID == groupID && $0.status == .failed }.max { $0.createdAt < $1.createdAt }
    }
    var groupMembers: [RoundUser] {
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
    var currentRoundResults: [RoundResult] {
        guard let groupID = currentGroup?.id else { return [] }
        return (snapshot?.roundResults ?? []).filter { $0.groupID == groupID }.sorted { $0.completedAt > $1.completedAt }
    }
    var currentPendingOperations: [PendingSyncOperation] {
        guard let snapshot, let groupID = currentGroup?.id else { return [] }
        let challengeIDs = Set(snapshot.challenges.filter { $0.groupID == groupID }.map(\.id))
        let submissionClientIDs = Set(snapshot.submissions.filter { challengeIDs.contains($0.challengeID) }.map(\.clientGeneratedID))
        return snapshot.pendingOperations.filter { submissionClientIDs.contains($0.clientGeneratedID) }
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
    var earliestProposalStartDate: Date {
        let now = environment.clock.now
        guard let active = currentChallenge, active.status == .active,
              let calendar = ScheduleEngine.calendar(for: active) else {
            return Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now
        }
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: active.endDate)) ?? active.endDate
    }

    func start() async {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-skipOnboarding") {
            hasCompletedOnboarding = true
            UserDefaults.standard.set(true, forKey: "round.onboarding.complete")
        }
        guard hasCompletedOnboarding else { return }
        await load(reset: arguments.contains("-resetDemo"))
    }

    func startDemo(reset: Bool = false) async {
        hasCompletedOnboarding = true
        isSignedIn = true
        UserDefaults.standard.set(true, forKey: "round.onboarding.complete")
        await load(reset: reset)
    }

    func handleAppleAuthorization(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error as ASAuthorizationError) where error.code == .canceled:
            errorBanner = String(localized: "Sign in was cancelled.")
        case .failure:
            errorBanner = String(localized: "Sign in could not be completed. Try again.")
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                errorBanner = String(localized: "Apple did not return a valid identity token.")
                return
            }
            do {
                try await environment.authService?.exchangeAppleIdentityToken(token)
                try environment.keychain.set(credential.user, for: "appleSubjectID")
                hasCompletedOnboarding = true
                isSignedIn = true
                UserDefaults.standard.set(true, forKey: "round.onboarding.complete")
                await load(reset: false)
            } catch {
                errorBanner = error.localizedDescription
            }
        }
    }

    func signUp(email: String, password: String, displayName: String) async {
        guard let auth = environment.authService else {
            errorBanner = String(localized: "Live sign-in is not configured.")
            return
        }
        do {
            try await auth.signUp(email: email, password: password, displayName: displayName)
            hasCompletedOnboarding = true
            isSignedIn = true
            UserDefaults.standard.set(true, forKey: "round.onboarding.complete")
            await load(reset: false)
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    func signIn(email: String, password: String) async {
        guard let auth = environment.authService else {
            errorBanner = String(localized: "Live sign-in is not configured.")
            return
        }
        do {
            try await auth.signIn(email: email, password: password)
            hasCompletedOnboarding = true
            isSignedIn = true
            UserDefaults.standard.set(true, forKey: "round.onboarding.complete")
            await load(reset: false)
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    @discardableResult
    private func applyCommand(_ command: RepositoryCommand, preferReturnedSnapshot: Bool = true) async -> Bool {
        do {
            if let updated = try await environment.repository.perform(command) {
                snapshot = SnapshotMigrator.migrate(updated)
            } else if preferReturnedSnapshot {
                await load(reset: false)
            }
            return true
        } catch {
            errorBanner = error.localizedDescription
            return false
        }
    }

    func load(reset: Bool) async {
        loadState = .loading
        do {
            snapshot = SnapshotMigrator.migrate(reset ? try await environment.repository.reset() : try await environment.repository.load())
            if ProcessInfo.processInfo.arguments.contains("-emptyDemo"), var emptySnapshot = snapshot {
                emptySnapshot.memberships.removeAll { $0.userID == emptySnapshot.currentUser.id }
                snapshot = emptySnapshot
            }
            if ProcessInfo.processInfo.arguments.contains("-noProposal"), var proposalSnapshot = snapshot {
                let openProposalIDs = Set(proposalSnapshot.proposals.filter { $0.status == .voting }.map(\.id))
                proposalSnapshot.proposals.removeAll { openProposalIDs.contains($0.id) }
                proposalSnapshot.votes.removeAll { openProposalIDs.contains($0.proposalID) }
                snapshot = proposalSnapshot
            }
            if !activeGroups.contains(where: { $0.id == activeGroupID }) { setActiveGroup(activeGroups.first?.id) }
            await reconcileAndPersist()
            await drainPending()
            await rebuildNotificationPlan()
            let arguments = ProcessInfo.processInfo.arguments
            if let tabFlag = arguments.firstIndex(of: "-tab"),
               arguments.indices.contains(tabFlag + 1),
               let requestedTab = Int(arguments[tabFlag + 1]),
               0...2 ~= requestedTab {
                selectedTab = requestedTab
            }
            isSignedIn = true
            loadState = currentGroup == nil ? .empty : .loaded
            presentPendingRouteIfPossible()
            AppLog.lifecycle.info("Loaded local app state with \(self.activeGroups.count, privacy: .public) active groups")
        } catch {
            loadState = .error(error.localizedDescription)
            AppLog.persistence.error("Failed to load app state: \(error.localizedDescription, privacy: .private)")
        }
    }

    func refresh() async {
        await load(reset: false)
    }

    func retryPending() async {
        guard var snapshot else { return }
        for operation in snapshot.pendingOperations {
            snapshot = environment.syncCoordinator.prepareManualRetry(snapshot, clientGeneratedID: operation.clientGeneratedID)
        }
        self.snapshot = snapshot
        await drainPending(force: true)
    }

    func logWorkout(
        quantity: Double,
        clips: [WorkoutClip] = [],
        sessionRequirementDate: Date? = nil,
        openedWhileWindowOpen: Bool = false
    ) async -> CheckInLogResult {
        guard var snapshot, let challenge = currentChallenge else {
            return .validationFailed(message: String(localized: "This round is no longer available."))
        }
        guard quantity > 0 else {
            return .validationFailed(message: String(localized: "Enter an amount greater than zero."))
        }
        guard WorkoutClipRules.areValid(clips, for: challenge.measurementType) else {
            return .validationFailed(message: String(localized: "Record a short workout clip before submitting."))
        }
        let now = environment.clock.now
        if let message = CheckInSubmissionRules.validationMessage(
            challenge: challenge,
            now: now,
            pinnedRequirementDate: sessionRequirementDate,
            openedWhileWindowOpen: openedWhileWindowOpen
        ) {
            // Keep the failure in-sheet; do not promote to a global banner that follows the user across tabs.
            return .validationFailed(message: message)
        }
        let originalSnapshot = snapshot
        let clientID = UUID()
        let requirementDate = CheckInSubmissionRules.requirementDate(
            challenge: challenge,
            now: now,
            pinnedRequirementDate: sessionRequirementDate
        )
        let submission = Submission(
            id: UUID(), clientGeneratedID: clientID, challengeID: challenge.id, userID: snapshot.currentUser.id,
            requirementDate: requirementDate, quantity: quantity, measurementType: challenge.measurementType,
            completedAt: now, submittedAt: now, syncState: .waiting, verificationState: .honourSystem,
            createdAt: now, updatedAt: now, clips: clips
        )
        snapshot.submissions.append(submission)
        snapshot.pendingOperations.append(.init(id: UUID(), clientGeneratedID: clientID, kind: .submission, retryCount: 0, nextRetryAt: now, createdAt: now, lastError: nil))
        let points = ScoringEngine.points(completedQuantity: quantity, minimumQuantity: challenge.minimumQuantity)
        self.snapshot = snapshot
        do {
            try await persist()
        } catch {
            self.snapshot = originalSnapshot
            let message = String(localized: "Your check-in could not be saved. Nothing was added, so please try again.")
            errorBanner = message
            AppLog.persistence.error("Failed to save local check-in: \(error.localizedDescription, privacy: .private)")
            return .persistenceFailed(message: message)
        }
        PendingWorkoutSessionStore.clear(challengeID: challenge.id, userID: snapshot.currentUser.id)
        notePendingWorkoutSessionChanged()
        await drainPending()
        scheduleBackgroundSyncIfNeeded()
        await rebuildNotificationPlan()
        await notifyFriendsOfSubmission(submission)
        let syncState = self.snapshot?.submissions.first(where: { $0.clientGeneratedID == clientID })?.syncState ?? .waiting
        showCompletion = true
        return .saved(points: points, syncState: syncState)
    }

    /// Live mode fans out APNs via Edge Function after sync. Demo relies on snapshot activity from sync.
    private func notifyFriendsOfSubmission(_ submission: Submission) async {
        guard let challenge = currentChallenge, let group = currentGroup, let snapshot else { return }
        let actorName = snapshot.users.first { $0.id == submission.userID }?.displayName ?? snapshot.currentUser.displayName
        _ = FriendPostedCopy.lockScreenBody(
            actorName: actorName,
            groupName: group.name,
            viewerHasCompleted: false
        )
        _ = challenge.title
        if mode == .live {
            // Remote push is handled by the submit-workout Edge Function after accept_submission.
        }
    }

    func castVote(_ choice: VoteChoice) async {
        guard requireConnection(), let proposal = currentProposal,
              proposal.status == .voting, proposal.votingEndsAt > environment.clock.now,
              proposal.eligibleVoterIDs.contains(snapshot?.currentUser.id ?? UUID()) else { return }
        guard await applyCommand(.castVote(proposalID: proposal.id, choice: choice)) else { return }
        await reconcileAndPersist()
        await rebuildNotificationPlan()
    }

    func useRecoveryDay() async {
        let now = environment.clock.now
        guard requireConnection(), let challenge = currentChallenge,
              (ScheduleEngine.completionInstant(for: challenge) ?? .distantPast) >= now, ScheduleEngine.isScheduled(on: now, challenge: challenge),
              !recoveryUsedToday, remainingRecoveryDays > 0 else { return }
        guard await applyCommand(.useRecoveryDay(challengeID: challenge.id)) else { return }
        await rebuildNotificationPlan()
    }

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
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func selectGroup(_ groupID: UUID) {
        guard activeGroups.contains(where: { $0.id == groupID }) else { return }
        setActiveGroup(groupID)
        selectedTab = min(selectedTab, 2)
        // Check-in window messaging is crew-scoped; drop a stale closed-window banner when switching.
        if errorBanner == CheckInSubmissionRules.closedWindowMessage {
            errorBanner = nil
        }
        Task { await rebuildNotificationPlan() }
    }

    func createProposal(from draft: ProposalDraft) async -> Bool {
        guard requireConnection(), let snapshot, let group = currentGroup else { return false }
        guard validateRoundDraft(draft, snapshot: snapshot, group: group) else { return false }
        guard await applyCommand(.createProposal(groupID: group.id, draft: draft)) else { return false }
        await rebuildNotificationPlan()
        return true
    }

    func startRound(from draft: ProposalDraft) async -> Bool {
        guard requireConnection(), let snapshot, let group = currentGroup else { return false }
        guard validateRoundDraft(draft, snapshot: snapshot, group: group) else { return false }
        let title = TextSanitizer.clean(draft.title, maximumLength: 52)
        guard await applyCommand(.startRound(groupID: group.id, draft: draft)) else { return false }
        await reconcileAndPersist()
        await rebuildNotificationPlan()
        noticeBanner = String(localized: "\(title) is ready.")
        return true
    }

    private func validateRoundDraft(_ draft: ProposalDraft, snapshot: DemoSnapshot, group: RoundGroup) -> Bool {
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

    func updateNotificationSettings(_ settings: UserNotificationSettings) async -> Bool {
        let previous = snapshot?.notificationSettings
        snapshot?.notificationSettings = settings
        guard await applyCommand(.updateNotificationSettings(settings)) else {
            snapshot?.notificationSettings = previous
            return false
        }
        await rebuildNotificationPlan()
        return true
    }

    func updateDisplayName(_ name: String) async {
        let clean = TextSanitizer.clean(name, maximumLength: 40)
        guard clean.count >= 2 else { return }
        _ = await applyCommand(.updateProfile(displayName: clean, appearance: nil, showsExactTotals: nil))
    }

    func setAppearance(_ appearance: AppearancePreference) async {
        _ = await applyCommand(.updateProfile(displayName: nil, appearance: appearance, showsExactTotals: nil))
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

    func block(_ user: RoundUser) async {
        if await applyCommand(.block(user.id)) {
            noticeBanner = String(localized: "Member blocked. Their activity is now hidden.")
        }
    }

    func unblock(userID: UUID) async {
        if await applyCommand(.unblock(userID)) {
            noticeBanner = String(localized: "Member unblocked.")
        }
    }

    func report(_ user: RoundUser, reason: String) async {
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

    func requestNotifications() async {
        if var settings = snapshot?.notificationSettings {
            settings.primerDismissed = true
            _ = await applyCommand(.updateNotificationSettings(settings))
        }
        do {
            let granted = try await environment.notifications.requestAuthorization()
            notificationsDenied = !granted
            notificationAuthorizationState = granted ? .authorized : .denied
            if !granted { errorBanner = String(localized: "Notifications are off. You can enable them later in Settings.") }
        } catch {
            errorBanner = String(localized: "Notification permission could not be requested.")
        }
        showNotificationPrimer = false
        await rebuildNotificationPlan()
    }

    func dismissNotificationPrimer() async {
        if var settings = snapshot?.notificationSettings {
            settings.primerDismissed = true
            _ = await applyCommand(.updateNotificationSettings(settings))
        }
        showNotificationPrimer = false
    }

    func handleURL(_ url: URL) {
        guard let route = AppRoute.parse(url) else {
            errorBanner = String(localized: "That Round invitation link is not valid.")
            AppLog.routing.notice("Rejected malformed invitation route")
            return
        }
        switch route {
        case .joinGroup(let code):
            pendingJoinCode = code
            presentPendingRouteIfPossible()
        case .logWorkout(let groupID):
            pendingLogWorkoutGroupID = groupID
            presentPendingRouteIfPossible()
        }
    }

    func clearPendingJoinRoute() { pendingJoinCode = nil }

    func consumePendingWorkoutSession() {
        presentWorkoutSession = false
        pendingLogWorkoutGroupID = nil
        pendingWorkoutSessionRevision += 1
    }

    func notePendingWorkoutSessionChanged() {
        pendingWorkoutSessionRevision += 1
    }

    func handleConnectivityChanged(_ connected: Bool) async {
        guard connected else { return }
        await drainPending()
        await reconcileAndPersist()
        await rebuildNotificationPlan()
    }

    func handleBecameActive() async {
        await reconcileAndPersist()
        await drainPending()
        await rebuildNotificationPlan()
    }

    func handleSignificantTimeChange() async {
        await reconcileAndPersist()
        await rebuildNotificationPlan()
    }

    func handleBackgroundTaskExpired() {
        scheduleBackgroundSyncIfNeeded()
    }

    func signOut() {
        boundaryTask?.cancel()
        environment.authService?.signOut()
        snapshot = nil
        isSignedIn = false
        hasCompletedOnboarding = false
        UserDefaults.standard.set(false, forKey: "round.onboarding.complete")
    }

    func deleteAccount() async {
        guard await applyCommand(.deleteAccount, preferReturnedSnapshot: false) else { return }
        await environment.notifications.replacePlan([])
        signOut()
    }

    private func persist() async throws {
        guard let snapshot else { return }
        try await environment.repository.save(snapshot)
    }

    @discardableResult
    private func saveOrShowError() async -> Bool {
        do {
            try await persist()
            return true
        } catch {
            errorBanner = error.localizedDescription
            return false
        }
    }

    private func requireConnection() -> Bool {
        guard !isOffline else {
            errorBanner = String(localized: "Connect to the internet to make this group change. Offline check-ins remain available.")
            return false
        }
        return true
    }

    private func setActiveGroup(_ groupID: UUID?) {
        activeGroupID = groupID
        if let groupID {
            UserDefaults.standard.set(groupID.uuidString, forKey: "round.activeGroupID")
        } else {
            UserDefaults.standard.removeObject(forKey: "round.activeGroupID")
        }
    }

    private func ensureNotificationSettings(for groupID: UUID) {
        guard var snapshot else { return }
        var settings = snapshot.notificationSettings ?? UserNotificationSettings.defaults(userID: snapshot.currentUser.id, groups: activeGroups)
        if !settings.groups.contains(where: { $0.groupID == groupID }) {
            settings.groups.append(.defaults(groupID: groupID))
        }
        snapshot.notificationSettings = settings
        self.snapshot = snapshot
    }

    private func reconcileAndPersist() async {
        guard let snapshot else { return }
        let result = RoundStateReconciler.reconcile(snapshot: snapshot, at: environment.clock.now)
        self.snapshot = result.snapshot
        if !result.events.isEmpty { AppLog.lifecycle.info("Reconciled \(result.events.count, privacy: .public) domain transitions") }
        await saveOrShowError()
        scheduleBoundary(result.nextBoundary)
    }

    private func scheduleBoundary(_ date: Date?) {
        boundaryTask?.cancel()
        guard let date else { return }
        boundaryTask = Task { [weak self] in
            guard let self else { return }
            try? await environment.clock.sleep(until: date)
            guard !Task.isCancelled else { return }
            await reconcileAndPersist()
            await rebuildNotificationPlan()
        }
    }

    private func drainPending(force: Bool = false) async {
        guard let snapshot else { return }
        self.snapshot = await environment.syncCoordinator.drain(snapshot, connected: !isOffline, force: force)
        sessionRecoveryRequired = self.snapshot?.pendingOperations.contains {
            $0.lastError == "Authentication required"
        } == true
        AppLog.sync.info("Pending check-in count is now \(self.snapshot?.pendingOperations.count ?? 0, privacy: .public)")
        await reconcileAndPersist()
        scheduleBackgroundSyncIfNeeded()
    }

    func beginSessionRecovery() {
        sessionRecoveryRequired = false
        signOut()
    }

    private func scheduleBackgroundSyncIfNeeded() {
        guard snapshot?.pendingOperations.isEmpty == false,
              let identifier = Bundle.main.bundleIdentifier.map({ "\($0).sync" }) else { return }
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresNetworkConnectivity = true
        request.earliestBeginDate = environment.clock.now.addingTimeInterval(15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func rebuildNotificationPlan() async {
        guard let snapshot else { return }
        let status = await environment.notifications.authorizationStatus()
        notificationsDenied = status == .denied
        switch status {
        case .notDetermined: notificationAuthorizationState = .undetermined
        case .denied: notificationAuthorizationState = .denied
        case .provisional, .ephemeral: notificationAuthorizationState = .provisional
        default: notificationAuthorizationState = .authorized
        }
        let settings = snapshot.notificationSettings ?? UserNotificationSettings.defaults(userID: snapshot.currentUser.id, groups: activeGroups)
        let suppressPrimer = ProcessInfo.processInfo.arguments.contains("-suppressNotificationPrimer")
        if status == .notDetermined,
           !suppressPrimer,
           !settings.primerDismissed,
           snapshot.challenges.contains(where: { activeGroups.map(\.id).contains($0.groupID) && ($0.status == .active || $0.status == .scheduled) }) {
            showNotificationPrimer = true
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            await environment.notifications.replacePlan([])
            return
        }
        await environment.notifications.replacePlan(NotificationPlanBuilder.build(snapshot: snapshot, now: environment.clock.now))
        AppLog.notifications.info("Rebuilt local notification plan")
    }

    private func presentPendingRouteIfPossible() {
        guard hasCompletedOnboarding, isSignedIn else { return }
        if let groupID = pendingLogWorkoutGroupID {
            selectGroup(groupID)
            selectedTab = 0
            presentWorkoutSession = true
            return
        }
        guard pendingJoinCode != nil else { return }
        selectedTab = currentGroup == nil ? 0 : 1
    }

    private static func inviteCode() -> String {
        let characters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).compactMap { _ in characters.randomElement() })
    }
}

struct ProposalDraft: Codable, Hashable, Sendable {
    var title = "30-Day Round"
    var activityName = "push-ups"
    var measurementType: MeasurementType = .repetitions
    var minimumQuantity: Double = 15
    var frequencyType: FrequencyType = .daily
    var scheduledWeekdays: Set<Int> = Set(1...7)
    var durationDays = 30
    var startDate = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) ?? .now
    var deadlineMinutes = 21 * 60
    var timezone = TimeZone.current.identifier
    var recoveryDays = 1

    init() {}

    init(proposal: ChallengeProposal, earliestStartDate: Date) {
        title = proposal.title
        activityName = proposal.activityType
        measurementType = proposal.measurementType
        minimumQuantity = proposal.minimumQuantity
        frequencyType = proposal.frequencyType
        scheduledWeekdays = proposal.scheduledWeekdays
        durationDays = proposal.durationDays
        startDate = max(proposal.proposedStartDate, earliestStartDate)
        deadlineMinutes = proposal.dailyDeadlineMinutes
        timezone = proposal.challengeTimezone
        recoveryDays = proposal.recoveryDayAllowance
    }
}
