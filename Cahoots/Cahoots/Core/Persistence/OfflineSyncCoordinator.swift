import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class OfflineSyncCoordinator {
    private let repository: any AppRepository
    private let clock: any AppClock
    /// Aggressive early retries so crew-visible sync recovers quickly while the app is open.
    private let retryDelays: [TimeInterval] = [1, 3, 8, 20, 60]
    private(set) var isDraining = false

    init(repository: any AppRepository, clock: any AppClock) {
        self.repository = repository
        self.clock = clock
    }

    func drain(_ source: DemoSnapshot, connected: Bool, force: Bool = false) async -> DemoSnapshot {
        guard connected, !isDraining else { return source }
        isDraining = true
        defer { isDraining = false }
        var snapshot = source
        var attemptedOperationIDs = Set<UUID>()

        while let operation = nextOperation(in: snapshot, force: force, excluding: attemptedOperationIDs) {
            attemptedOperationIDs.insert(operation.id)
            guard let submission = snapshot.submissions.first(where: { $0.clientGeneratedID == operation.clientGeneratedID }) else {
                snapshot.pendingOperations.removeAll { $0.id == operation.id }
                try? await repository.save(snapshot)
                continue
            }
            AppLog.sync.info(
                "drain attempt clientID=\(operation.clientGeneratedID.uuidString, privacy: .public) retry=\(operation.retryCount, privacy: .public)"
            )
            let challengeTimezone = snapshot.challenges.first(where: { $0.id == submission.challengeID })?.challengeTimezone ?? "UTC"
            let result = await repository.syncSubmission(submission, challengeTimezone: challengeTimezone)
            apply(result, operation: operation, submission: submission, to: &snapshot)
            try? await repository.save(snapshot)
            if case .authenticationRequired = result { break }
        }
        return snapshot
    }

    func prepareManualRetry(_ source: DemoSnapshot, clientGeneratedID: UUID) -> DemoSnapshot {
        var snapshot = source
        if let operationIndex = snapshot.pendingOperations.firstIndex(where: { $0.clientGeneratedID == clientGeneratedID }) {
            snapshot.pendingOperations[operationIndex].retryCount = 0
            snapshot.pendingOperations[operationIndex].nextRetryAt = clock.now
            snapshot.pendingOperations[operationIndex].lastError = nil
        }
        if let submissionIndex = snapshot.submissions.firstIndex(where: { $0.clientGeneratedID == clientGeneratedID }) {
            snapshot.submissions[submissionIndex].syncState = .waiting
            snapshot.submissions[submissionIndex].updatedAt = clock.now
        }
        return snapshot
    }

    /// Soonest auto-retry for waiting (non-failed) pending ops, if any.
    func earliestAutoRetryDate(in snapshot: DemoSnapshot) -> Date? {
        snapshot.pendingOperations.compactMap { operation -> Date? in
            guard let submission = snapshot.submissions.first(where: { $0.clientGeneratedID == operation.clientGeneratedID }),
                  submission.syncState == .waiting else { return nil }
            return operation.nextRetryAt
        }.min()
    }

    private func nextOperation(in snapshot: DemoSnapshot, force: Bool, excluding attempted: Set<UUID>) -> PendingSyncOperation? {
        snapshot.pendingOperations
            .filter { operation in
                guard !attempted.contains(operation.id) else { return false }
                guard operation.kind == .submission,
                      let submission = snapshot.submissions.first(where: { $0.clientGeneratedID == operation.clientGeneratedID }),
                      submission.syncState != .rejected else { return false }
                if submission.syncState == .failed && !force { return false }
                return force || operation.nextRetryAt <= clock.now
            }
            .sorted { $0.createdAt < $1.createdAt }
            .first
    }

    private func apply(
        _ result: SubmissionSyncResult,
        operation: PendingSyncOperation,
        submission: Submission,
        to snapshot: inout DemoSnapshot
    ) {
        guard let submissionIndex = snapshot.submissions.firstIndex(where: { $0.clientGeneratedID == submission.clientGeneratedID }) else { return }
        let clientID = submission.clientGeneratedID.uuidString
        switch result {
        case .accepted(let receipt, let uploadedClips):
            AppLog.sync.info(
                "drain result accepted clientID=\(clientID, privacy: .public) submissionID=\(receipt.submissionID.uuidString, privacy: .public)"
            )
            mergeUploadedClips(uploadedClips, into: &snapshot.submissions[submissionIndex])
            snapshot.submissions[submissionIndex].id = receipt.submissionID
            snapshot.submissions[submissionIndex].syncState = .synced
            snapshot.submissions[submissionIndex].verificationState = .accepted
            snapshot.submissions[submissionIndex].updatedAt = receipt.acceptedAt
            snapshot.pendingOperations.removeAll { $0.id == operation.id }
            applyAcceptedScore(for: snapshot.submissions[submissionIndex], to: &snapshot)
        case .rejected(let reason):
            AppLog.sync.error(
                "drain result rejected clientID=\(clientID, privacy: .public) reason=\(reason, privacy: .public)"
            )
            snapshot.submissions[submissionIndex].syncState = .rejected
            snapshot.submissions[submissionIndex].verificationState = .rejected
            snapshot.submissions[submissionIndex].updatedAt = clock.now
            snapshot.submissions[submissionIndex].rejectionReason = reason
            snapshot.pendingOperations.removeAll { $0.id == operation.id }
            if !reason.isEmpty { snapshot.pendingOperations.removeAll { $0.clientGeneratedID == submission.clientGeneratedID } }
        case .retryable(let reason, let retryAfter, let uploadedClips):
            AppLog.sync.error(
                "drain result retryable clientID=\(clientID, privacy: .public) reason=\(reason, privacy: .public)"
            )
            mergeUploadedClips(uploadedClips, into: &snapshot.submissions[submissionIndex])
            guard let operationIndex = snapshot.pendingOperations.firstIndex(where: { $0.id == operation.id }) else { return }
            let retriesScheduled = snapshot.pendingOperations[operationIndex].retryCount
            snapshot.pendingOperations[operationIndex].lastError = reason
            if retriesScheduled >= retryDelays.count {
                snapshot.submissions[submissionIndex].syncState = .failed
                snapshot.pendingOperations[operationIndex].nextRetryAt = .distantFuture
            } else {
                snapshot.pendingOperations[operationIndex].retryCount = retriesScheduled + 1
                snapshot.submissions[submissionIndex].syncState = .waiting
                let delay = retryAfter ?? retryDelays[retriesScheduled]
                snapshot.pendingOperations[operationIndex].nextRetryAt = clock.now.addingTimeInterval(delay)
            }
            snapshot.submissions[submissionIndex].updatedAt = clock.now
        case .authenticationRequired(let uploadedClips):
            AppLog.sync.error("drain result auth-required clientID=\(clientID, privacy: .public)")
            mergeUploadedClips(uploadedClips, into: &snapshot.submissions[submissionIndex])
            if let operationIndex = snapshot.pendingOperations.firstIndex(where: { $0.id == operation.id }) {
                snapshot.pendingOperations[operationIndex].lastError = "Authentication required"
                snapshot.pendingOperations[operationIndex].nextRetryAt = clock.now.addingTimeInterval(60)
            }
        }
    }

    private func mergeUploadedClips(_ clips: [WorkoutClip], into submission: inout Submission) {
        guard !clips.isEmpty else { return }
        var merged = submission.clips
        for clip in clips {
            if let index = merged.firstIndex(where: { $0.id == clip.id }) {
                if clip.remotePath != nil {
                    merged[index].remotePath = clip.remotePath
                }
                if clip.localFilename != nil {
                    merged[index].localFilename = clip.localFilename
                }
            } else {
                merged.append(clip)
            }
        }
        submission.clips = merged
    }

    private func applyAcceptedScore(for submission: Submission, to snapshot: inout DemoSnapshot) {
        guard let challenge = snapshot.challenges.first(where: { $0.id == submission.challengeID }),
              let key = RequirementKey(challenge: challenge, userID: submission.userID, date: submission.requirementDate) else { return }
        let points = ScoringEngine.points(completedQuantity: submission.quantity, minimumQuantity: challenge.minimumQuantity)
        guard points > 0 else { return }
        let baseKey = "\(key.challengeID.uuidString):\(key.userID.uuidString):\(key.dateToken):\(ScoreEventType.requirementCompleted.rawValue)"
        guard !snapshot.scoreEvents.contains(where: { $0.scoringKey == baseKey }) else { return }

        snapshot.scoreEvents.append(.init(
            id: UUID(), challengeID: challenge.id, userID: submission.userID, submissionID: submission.id,
            eventType: .requirementCompleted, points: 100, reason: "Scheduled requirement completed",
            scoringVersion: challenge.scoringVersion, createdAt: clock.now,
            requirementDate: submission.requirementDate, scoringKey: baseKey
        ))
        if points > 100 {
            snapshot.scoreEvents.append(.init(
                id: UUID(), challengeID: challenge.id, userID: submission.userID, submissionID: submission.id,
                eventType: .bonus, points: points - 100, reason: "Capped completion bonus",
                scoringVersion: challenge.scoringVersion, createdAt: clock.now,
                requirementDate: submission.requirementDate,
                scoringKey: "\(key.challengeID.uuidString):\(key.userID.uuidString):\(key.dateToken):\(ScoreEventType.bonus.rawValue)"
            ))
        }
        if let entryIndex = snapshot.leaderboard.firstIndex(where: {
            $0.user.id == submission.userID && ($0.groupID == challenge.groupID || $0.groupID == nil) && ($0.challengeID == challenge.id || $0.challengeID == nil)
        }) {
            snapshot.leaderboard[entryIndex].groupID = challenge.groupID
            snapshot.leaderboard[entryIndex].challengeID = challenge.id
            LeaderboardLedger.refresh(in: &snapshot)
            snapshot.leaderboard[entryIndex].currentStreak = projectedStreak(userID: submission.userID, challenge: challenge, snapshot: snapshot)
            snapshot.leaderboard[entryIndex].longestStreak = max(snapshot.leaderboard[entryIndex].longestStreak, snapshot.leaderboard[entryIndex].currentStreak)
        }
        if !snapshot.activity.contains(where: {
            $0.groupID == challenge.groupID && $0.actorID == submission.userID && $0.eventType == .completion && ScheduleEngine.isSameRequirementDay($0.createdAt, submission.requirementDate, challenge: challenge)
        }) {
            let actor = snapshot.users.first { $0.id == submission.userID }
            snapshot.activity.insert(.init(
                id: UUID(), groupID: challenge.groupID, actorID: submission.userID,
                actorName: actor?.displayName ?? "A member", eventType: .completion,
                message: submission.userID == snapshot.currentUser.id ? "You completed today’s challenge." : "\(actor?.displayName ?? "A member") completed today’s challenge.",
                createdAt: clock.now
            ), at: 0)
        }
    }

    private func projectedStreak(userID: UUID, challenge: CahootsChallenge, snapshot: DemoSnapshot) -> Int {
        guard let calendar = ScheduleEngine.calendar(for: challenge) else { return 0 }
        let completedDates = Set(snapshot.submissions.filter {
            $0.challengeID == challenge.id && $0.userID == userID && $0.verificationState == .accepted &&
            ScoringEngine.points(completedQuantity: $0.quantity, minimumQuantity: challenge.minimumQuantity) > 0
        }.map { calendar.startOfDay(for: $0.requirementDate) })
        let recoveryDates = Set(snapshot.recoveryDays.filter {
            $0.challengeID == challenge.id && $0.userID == userID
        }.map { calendar.startOfDay(for: $0.requirementDate) })
        let scheduled = ScheduleEngine.scheduledDates(for: challenge, through: clock.now).filter { date in
            completedDates.contains(calendar.startOfDay(for: date)) || recoveryDates.contains(calendar.startOfDay(for: date)) || (ScheduleEngine.deadline(for: date, challenge: challenge) ?? .distantFuture) <= clock.now
        }
        return StreakEngine.currentStreak(scheduledDates: scheduled, completedDates: completedDates, recoveryDates: recoveryDates, calendar: calendar)
    }
}
