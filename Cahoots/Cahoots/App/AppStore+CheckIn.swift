import Foundation
import OSLog

extension AppStore {
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
        let requirementToken = ScheduleEngine.requirementDateToken(for: requirementDate, challenge: challenge) ?? "unknown"
        AppLog.sync.info(
            "logWorkout start challengeID=\(challenge.id.uuidString, privacy: .public) quantity=\(quantity, privacy: .public) clips=\(clips.count, privacy: .public) requirementDate=\(requirementToken, privacy: .public) clientID=\(clientID.uuidString, privacy: .public)"
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
            AppLog.sync.error("logWorkout persistence failed clientID=\(clientID.uuidString, privacy: .public)")
            return .persistenceFailed(message: message)
        }
        PendingWorkoutSessionStore.clear(challengeID: challenge.id, userID: snapshot.currentUser.id)
        notePendingWorkoutSessionChanged()
        await drainPending()
        scheduleBackgroundSyncIfNeeded()
        await rebuildNotificationPlan()
        await notifyFriendsOfSubmission(submission)
        let syncState = self.snapshot?.submissions.first(where: { $0.clientGeneratedID == clientID })?.syncState ?? .waiting
        AppLog.sync.info(
            "logWorkout saved clientID=\(clientID.uuidString, privacy: .public) points=\(points, privacy: .public) syncState=\(String(describing: syncState), privacy: .public)"
        )
        showCompletion = true
        return .saved(points: points, syncState: syncState)
    }

    func logTodayCheckInDiagnostics(context: String) {
        let hasToday = todaySubmission != nil
        let points = todayPoints
        let peers = todayPeerCheckIns.count
        let reveal = canRevealTodayQuantities
        let challengeID = currentChallenge?.id.uuidString ?? "none"
        AppLog.sync.info(
            "today state after \(context, privacy: .public) challengeID=\(challengeID, privacy: .public) hasTodaySubmission=\(hasToday, privacy: .public) todayPoints=\(points, privacy: .public) peerCheckIns=\(peers, privacy: .public) revealUnlocked=\(reveal, privacy: .public)"
        )
    }

    /// Live mode fans out APNs via Edge Function after sync. Demo relies on snapshot activity from sync.
    func notifyFriendsOfSubmission(_ submission: Submission) async {
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
        guard requireConnection() else { return }
        guard let proposal = currentProposal else {
            errorBanner = String(localized: "There is no open vote right now.")
            return
        }
        guard proposal.status == .voting else {
            errorBanner = String(localized: "This proposal is not open for voting.")
            return
        }
        guard proposal.votingEndsAt > environment.clock.now else {
            errorBanner = String(localized: "Voting has closed for this proposal.")
            return
        }
        guard let userID = snapshot?.currentUser.id, proposal.eligibleVoterIDs.contains(userID) else {
            errorBanner = String(localized: "You are not eligible to vote on this proposal.")
            return
        }
        guard await applyCommand(.castVote(proposalID: proposal.id, choice: choice)) else { return }
        await reconcileAndPersist()
        await rebuildNotificationPlan()
    }

    func useRecoveryDay() async {
        let now = environment.clock.now
        guard requireConnection() else { return }
        guard let challenge = currentChallenge else {
            errorBanner = String(localized: "There is no active challenge to recover.")
            return
        }
        guard (ScheduleEngine.completionInstant(for: challenge) ?? .distantPast) >= now else {
            errorBanner = String(localized: "This round has ended.")
            return
        }
        guard ScheduleEngine.isScheduled(on: now, challenge: challenge) else {
            errorBanner = String(localized: "Today is not a scheduled requirement day.")
            return
        }
        guard !recoveryUsedToday else {
            errorBanner = String(localized: "You already used a recovery day today.")
            return
        }
        guard remainingRecoveryDays > 0 else {
            errorBanner = String(localized: "No recovery days remain for this round.")
            return
        }
        guard await applyCommand(.useRecoveryDay(challengeID: challenge.id)) else { return }
        await rebuildNotificationPlan()
    }
}
