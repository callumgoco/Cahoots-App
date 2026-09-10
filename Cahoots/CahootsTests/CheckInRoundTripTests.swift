import Foundation
import Testing
@testable import Cahoots

struct CheckInWireDateEncodingTests {
    @Test func londonChallengeLocalMidnightWiresAsCalendarDayNotUTCDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10))!
        let localMidnight = calendar.startOfDay(for: day)

        // Bug we fixed: formatting this instant in UTC yields 2026-09-09 during BST.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let utcToken = String(format: "%04d-%02d-%02d",
                              utc.component(.year, from: localMidnight),
                              utc.component(.month, from: localMidnight),
                              utc.component(.day, from: localMidnight))
        #expect(utcToken == "2026-09-09")

        let wire = ScheduleEngine.requirementDateToken(for: localMidnight, timeZoneIdentifier: "Europe/London")
        #expect(wire == "2026-09-10")
    }

    @Test func losAngelesChallengeLocalMidnightWiresAsCalendarDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10))!
        let localMidnight = calendar.startOfDay(for: day)
        let wire = ScheduleEngine.requirementDateToken(for: localMidnight, timeZoneIdentifier: "America/Los_Angeles")
        #expect(wire == "2026-09-10")
    }

    @Test func clipPathUsesChallengeTimezoneToken() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10))!
        let localMidnight = calendar.startOfDay(for: day)
        let groupID = UUID()
        let challengeID = UUID()
        let userID = UUID()
        let clipID = UUID()
        let path = "\(groupID.uuidString)/\(challengeID.uuidString)/2026-09-10/\(userID.uuidString)/\(clipID.uuidString).mov"
        #expect(WorkoutClipPathRules.isValid(
            storagePath: path,
            groupID: groupID,
            challengeID: challengeID,
            userID: userID,
            requirementDate: localMidnight,
            challengeTimezone: "Europe/London"
        ))
        let wrongDayPath = "\(groupID.uuidString)/\(challengeID.uuidString)/2026-09-09/\(userID.uuidString)/\(clipID.uuidString).mov"
        #expect(!WorkoutClipPathRules.isValid(
            storagePath: wrongDayPath,
            groupID: groupID,
            challengeID: challengeID,
            userID: userID,
            requirementDate: localMidnight,
            challengeTimezone: "Europe/London"
        ))
    }
}

@MainActor
private final class RecordingSyncRepository: AppRepository {
    var mode: AppMode = .demo
    var lastTimezone: String?
    var lastDateToken: String?
    var syncedSubmissions: [Submission] = []

    func load() async throws -> DemoSnapshot { DemoSeed.make() }
    func save(_ snapshot: DemoSnapshot) async throws {}
    func reset() async throws -> DemoSnapshot { DemoSeed.make() }

    func syncSubmission(_ submission: Submission, challengeTimezone: String) async -> SubmissionSyncResult {
        lastTimezone = challengeTimezone
        lastDateToken = ScheduleEngine.requirementDateToken(
            for: submission.requirementDate,
            timeZoneIdentifier: challengeTimezone
        )
        var copy = submission
        if copy.clips.contains(where: { $0.remotePath == nil }) {
            copy.clips = copy.clips.map { clip in
                var updated = clip
                if updated.remotePath == nil {
                    updated.remotePath = "group/\(submission.challengeID.uuidString)/\(lastDateToken ?? "unknown")/\(submission.userID.uuidString)/\(clip.id.uuidString).mov"
                }
                return updated
            }
        }
        syncedSubmissions.append(copy)
        return .accepted(.init(submissionID: submission.id, acceptedAt: .now))
    }

    func perform(_ command: RepositoryCommand) async throws -> DemoSnapshot? { nil }

    func requestClipUploadURL(groupID: UUID, challengeID: UUID, requirementDateToken: String, clipID: UUID) async throws -> ClipUploadTicket {
        lastDateToken = requirementDateToken
        return ClipUploadTicket(
            storagePath: "\(groupID.uuidString)/\(challengeID.uuidString)/\(requirementDateToken)/user/\(clipID.uuidString).mov",
            uploadURL: URL(fileURLWithPath: "/dev/null"),
            token: nil,
            clipID: clipID
        )
    }

    func uploadClip(ticket: ClipUploadTicket, fileURL: URL) async throws {}
    func requestClipDownloadURL(clipID: UUID) async throws -> ClipDownloadTicket {
        ClipDownloadTicket(downloadURL: URL(fileURLWithPath: "/dev/null"), storagePath: "x.mov", clipID: clipID, expiresIn: 60)
    }
}

struct CheckInRoundTripFlowTests {
    @MainActor
    @Test func londonCheckInSurvivesSnapshotRoundTripAndUnlocksPeerClips() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10))!
        let afternoon = calendar.date(byAdding: .hour, value: 15, to: day)!
        let requirementDay = calendar.startOfDay(for: day)

        let you = CahootsUser(
            id: UUID(), appleSubjectID: nil, displayName: "You", avatarPath: nil,
            timezoneIdentifier: "Europe/London", createdAt: day, updatedAt: afternoon, deletedAt: nil, showsExactTotals: true
        )
        let peer = CahootsUser(
            id: UUID(), appleSubjectID: nil, displayName: "Peer", avatarPath: nil,
            timezoneIdentifier: "Europe/London", createdAt: day, updatedAt: afternoon, deletedAt: nil, showsExactTotals: true
        )
        let groupID = UUID()
        let challenge = CahootsChallenge(
            id: UUID(), groupID: groupID, proposalID: nil, title: "Push-ups", activityType: "push-ups",
            measurementType: .repetitions, minimumQuantity: 15, frequencyType: .daily,
            scheduledWeekdays: Set(1...7), timesPerWeek: nil, startDate: day.addingTimeInterval(-5 * 86_400),
            endDate: day.addingTimeInterval(10 * 86_400), challengeTimezone: "Europe/London",
            dailyDeadlineMinutes: 23 * 60, recoveryDayAllowance: 2, status: .active,
            scoringVersion: 1, createdAt: day
        )

        let clipID = UUID()
        let localClip = WorkoutClip(
            id: clipID, kind: .set, durationSeconds: 5,
            localFilename: "local.mov", remotePath: nil, createdAt: afternoon
        )
        let clientID = UUID()
        let pending = Submission(
            id: UUID(), clientGeneratedID: clientID, challengeID: challenge.id, userID: you.id,
            requirementDate: requirementDay, quantity: 15, measurementType: .repetitions,
            completedAt: afternoon, submittedAt: afternoon, syncState: .waiting,
            verificationState: .honourSystem, createdAt: afternoon, updatedAt: afternoon,
            clips: [localClip]
        )

        var snapshot = DemoSnapshot(
            schemaVersion: 3,
            currentUser: you,
            users: [you, peer],
            groups: [CahootsGroup(id: groupID, name: "Crew", emoji: "⚡️", ownerID: you.id, memberLimit: 8, createdAt: day, updatedAt: afternoon, archivedAt: nil)],
            memberships: [
                GroupMembership(id: UUID(), groupID: groupID, userID: you.id, role: .owner, status: .active, joinedAt: day, leftAt: nil, notificationLevel: .immediate),
                GroupMembership(id: UUID(), groupID: groupID, userID: peer.id, role: .member, status: .active, joinedAt: day, leftAt: nil, notificationLevel: .immediate)
            ],
            invites: [],
            challenges: [challenge],
            proposals: [],
            votes: [],
            submissions: [pending],
            scoreEvents: [],
            leaderboard: [
                LeaderboardEntry(user: you, points: 0, completedRequirements: 0, scheduledRequirements: 10, currentStreak: 0, longestStreak: 0, finalScoreAchievedAt: afternoon, previousRank: nil, groupID: groupID, challengeID: challenge.id),
                LeaderboardEntry(user: peer, points: 0, completedRequirements: 0, scheduledRequirements: 10, currentStreak: 0, longestStreak: 0, finalScoreAchievedAt: afternoon, previousRank: nil, groupID: groupID, challengeID: challenge.id)
            ],
            allTimeLeaderboard: [],
            activity: [],
            notificationPreference: NotificationPreference(
                id: UUID(), userID: you.id, groupID: nil, personalRemindersEnabled: true,
                friendActivityMode: .immediate, challengeUpdatesEnabled: true,
                quietHoursStart: 22 * 60, quietHoursEnd: 7 * 60, reminderMinutes: 18 * 60
            ),
            notificationSettings: .defaults(userID: you.id, groups: []),
            pendingOperations: [
                PendingSyncOperation(id: UUID(), clientGeneratedID: clientID, kind: .submission, retryCount: 0, nextRetryAt: afternoon, createdAt: afternoon, lastError: nil)
            ],
            recoveryDays: [],
            previousRound: nil,
            roundResults: [],
            appearance: .system,
            reports: [],
            blockedUsers: []
        )

        let repository = RecordingSyncRepository()
        let coordinator = OfflineSyncCoordinator(repository: repository, clock: FixedAppClock(now: afternoon))
        snapshot = await coordinator.drain(snapshot, connected: true)

        #expect(repository.lastTimezone == "Europe/London")
        #expect(repository.lastDateToken == "2026-09-10")
        #expect(snapshot.pendingOperations.isEmpty)
        #expect(snapshot.submissions.first?.syncState == .synced)
        #expect(ScoringEngine.points(completedQuantity: 15, minimumQuantity: 15) == 100)
        #expect(snapshot.scoreEvents.contains { $0.eventType == .requirementCompleted && $0.points == 100 })
        #expect(snapshot.leaderboard.first { $0.user.id == you.id }?.points == 100)
        #expect(snapshot.activity.contains { $0.eventType == .completion })

        // Simulate app-snapshot re-encoding the Postgres date as challenge-local midnight.
        let serverRequirementDate = ScheduleEngine.date(fromWireToken: "2026-09-10", timeZoneIdentifier: "Europe/London")!
        var serverSubmission = snapshot.submissions[0]
        serverSubmission.requirementDate = serverRequirementDate
        serverSubmission.syncState = .synced
        serverSubmission.clips = [
            WorkoutClip(
                id: clipID, kind: .set, durationSeconds: 5,
                localFilename: nil,
                remotePath: "\(groupID.uuidString)/\(challenge.id.uuidString)/2026-09-10/\(you.id.uuidString)/\(clipID.uuidString).mov",
                createdAt: afternoon
            )
        ]

        let peerClip = WorkoutClip(
            id: UUID(), kind: .set, durationSeconds: 4,
            localFilename: nil,
            remotePath: "\(groupID.uuidString)/\(challenge.id.uuidString)/2026-09-10/\(peer.id.uuidString)/peer.mov",
            createdAt: afternoon
        )
        let peerSubmission = Submission(
            id: UUID(), clientGeneratedID: UUID(), challengeID: challenge.id, userID: peer.id,
            requirementDate: serverRequirementDate, quantity: 20, measurementType: .repetitions,
            completedAt: afternoon, submittedAt: afternoon, syncState: .synced,
            verificationState: .accepted, createdAt: afternoon, updatedAt: afternoon,
            clips: [peerClip]
        )

        let afterRefresh = LocalSnapshotStore.merge(
            server: {
                var server = snapshot
                server.submissions = [serverSubmission, peerSubmission]
                server.pendingOperations = []
                return server
            }(),
            overlay: LiveOfflineOverlay(pendingOperations: [], submissions: [])
        )

        #expect(ScheduleEngine.isSameRequirementDay(serverRequirementDate, afternoon, challenge: challenge))

        let ownToday = afterRefresh.submissions.filter {
            $0.userID == you.id && ScheduleEngine.isSameRequirementDay($0.requirementDate, afternoon, challenge: challenge)
        }
        #expect(ownToday.count == 1)
        #expect(ScoringEngine.points(completedQuantity: ownToday[0].quantity, minimumQuantity: challenge.minimumQuantity) == 100)

        let peerToday = afterRefresh.submissions.filter {
            $0.userID == peer.id && ScheduleEngine.isSameRequirementDay($0.requirementDate, afternoon, challenge: challenge)
        }
        #expect(peerToday.count == 1)

        // Spoiler: incomplete viewer cannot see peer clip paths.
        let locked = CheckInVisibility.redacted(peerToday[0], reveal: false)
        #expect(locked.quantity == 0)
        #expect(locked.clips.first?.remotePath == nil)
        #expect(PeerClipPlayback.playableClip(from: locked) == nil)

        // After own completion, spoilers unlock and peer clip is playable.
        #expect(CheckInVisibility.canRevealToday(viewerHasCompleted: true, usedRecovery: false, now: afternoon, deadline: ScheduleEngine.deadline(for: afternoon, challenge: challenge)))
        let unlocked = CheckInVisibility.redacted(peerToday[0], reveal: true)
        #expect(unlocked.quantity == 20)
        #expect(PeerClipPlayback.playableClip(from: unlocked)?.remotePath != nil)

        let statuses = TodayCrewStatusBuilder.statuses(
            members: [you, peer],
            submissions: afterRefresh.submissions,
            recoveries: [],
            challenge: challenge,
            now: afternoon,
            currentUserID: you.id
        )
        #expect(statuses.first { $0.user.id == you.id }?.status == .done)
        #expect(statuses.first { $0.user.id == peer.id }?.status == .done)

        let friendCopy = FriendPostedCopy.lockScreenBody(
            actorName: peer.displayName,
            groupName: "Crew",
            viewerHasCompleted: true
        )
        #expect(friendCopy.contains("just posted"))
    }

    @MainActor
    @Test func wrongUTCDateTokenWouldMissTodayAfterRefresh() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10))!
        let afternoon = calendar.date(byAdding: .hour, value: 15, to: day)!
        let challenge = CahootsChallenge(
            id: UUID(), groupID: UUID(), proposalID: nil, title: "Push-ups", activityType: "push-ups",
            measurementType: .repetitions, minimumQuantity: 15, frequencyType: .daily,
            scheduledWeekdays: Set(1...7), timesPerWeek: nil, startDate: day,
            endDate: day.addingTimeInterval(10 * 86_400), challengeTimezone: "Europe/London",
            dailyDeadlineMinutes: 23 * 60, recoveryDayAllowance: 2, status: .active,
            scoringVersion: 1, createdAt: day
        )
        // Stored as yesterday because ISO instant was cast in UTC — must NOT match today.
        let wrongDay = ScheduleEngine.date(fromWireToken: "2026-09-09", timeZoneIdentifier: "Europe/London")!
        #expect(!ScheduleEngine.isSameRequirementDay(wrongDay, afternoon, challenge: challenge))
        let rightDay = ScheduleEngine.date(fromWireToken: "2026-09-10", timeZoneIdentifier: "Europe/London")!
        #expect(ScheduleEngine.isSameRequirementDay(rightDay, afternoon, challenge: challenge))
    }
}
