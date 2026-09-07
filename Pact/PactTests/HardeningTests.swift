import Foundation
import Testing
@testable import Pact

struct LifecycleHardeningTests {
    @Test func expiredPassingVoteCreatesOneScheduledChallenge() {
        let now = Date.now
        var snapshot = DemoSeed.make(now: now)
        guard let proposalIndex = snapshot.proposals.firstIndex(where: { $0.status == .voting }) else {
            Issue.record("Missing proposal")
            return
        }
        let proposalID = snapshot.proposals[proposalIndex].id
        snapshot.proposals[proposalIndex].votingEndsAt = now.addingTimeInterval(-1)
        snapshot.votes = Array(snapshot.proposals[proposalIndex].eligibleVoterIDs.prefix(4)).map {
            Vote(id: UUID(), proposalID: proposalID, userID: $0, choice: .accept, createdAt: now, updatedAt: now)
        }

        let first = RoundStateReconciler.reconcile(snapshot: snapshot, at: now)
        let second = RoundStateReconciler.reconcile(snapshot: first.snapshot, at: now)
        #expect(first.snapshot.proposals[proposalIndex].status == .passed)
        #expect(first.snapshot.challenges.filter { $0.proposalID == proposalID }.count == 1)
        #expect(second.snapshot.challenges.filter { $0.proposalID == proposalID }.count == 1)
        #expect(second.snapshot.activity.filter { $0.eventType == .voteCompleted && $0.groupID == snapshot.proposals[proposalIndex].groupID }.count == 1)
    }

    @Test func scheduledChallengeActivatesAndCompletesAtTimezoneDeadline() {
        let now = Date.now
        var snapshot = DemoSeed.make(now: now)
        let groupID = snapshot.groups[0].id
        let challengeID = UUID()
        let challenge = RoundChallenge(
            id: challengeID, groupID: groupID, proposalID: nil, title: "Boundary",
            activityType: "stretching minutes", measurementType: .minutes, minimumQuantity: 10,
            frequencyType: .daily, scheduledWeekdays: Set(1...7), timesPerWeek: nil,
            startDate: now.addingTimeInterval(-2 * 86_400), endDate: now.addingTimeInterval(-86_400),
            challengeTimezone: "Europe/London", dailyDeadlineMinutes: 1, recoveryDayAllowance: 0,
            status: .scheduled, scoringVersion: 1, createdAt: now.addingTimeInterval(-3 * 86_400)
        )
        snapshot.challenges.append(challenge)
        let result = RoundStateReconciler.reconcile(snapshot: snapshot, at: now)
        #expect(result.snapshot.challenges.first { $0.id == challengeID }?.status == .completed)
        #expect(result.snapshot.roundResults?.contains { $0.challengeID == challengeID } == true)
    }

    @Test func migrationCreatesGroupScopedState() {
        var snapshot = DemoSeed.make()
        snapshot.schemaVersion = nil
        snapshot.notificationSettings = nil
        snapshot.roundResults = nil
        for index in snapshot.leaderboard.indices {
            snapshot.leaderboard[index].groupID = nil
            snapshot.leaderboard[index].challengeID = nil
        }
        let migrated = SnapshotMigrator.migrate(snapshot)
        #expect(migrated.schemaVersion == 3)
        #expect(migrated.notificationSettings != nil)
        #expect(migrated.roundResults != nil)
        #expect(migrated.leaderboard.allSatisfy { $0.groupID != nil })
    }

    @Test func startNowCreatesScheduledChallengeWithLeaderboardEntries() {
        let now = Date.now
        var snapshot = DemoSeed.make(now: now)
        let group = snapshot.groups[0]
        let challenge = ChallengeFactory.makeChallenge(
            groupID: group.id,
            title: "14-Day Walk Round",
            activityType: "walking minutes",
            measurementType: .minutes,
            minimumQuantity: 20,
            frequencyType: .daily,
            scheduledWeekdays: Set(1...7),
            durationDays: 14,
            startDate: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now,
            challengeTimezone: "Europe/London",
            dailyDeadlineMinutes: 21 * 60,
            recoveryDayAllowance: 1,
            createdAt: now
        )
        snapshot.challenges.append(challenge)
        ChallengeFactory.seedLeaderboardEntries(for: challenge, in: &snapshot, at: now)
        let memberCount = snapshot.memberships.filter { $0.groupID == group.id && $0.status == .active }.count
        #expect(challenge.status == .scheduled)
        #expect(snapshot.leaderboard.filter { $0.challengeID == challenge.id }.count == memberCount)
        #expect(snapshot.leaderboard.filter { $0.challengeID == challenge.id }.allSatisfy { $0.points == 0 })

        let proposal = ChallengeProposal(
            id: UUID(), groupID: group.id, proposedBy: snapshot.currentUser.id, title: challenge.title,
            activityType: challenge.activityType, measurementType: challenge.measurementType,
            minimumQuantity: challenge.minimumQuantity, frequencyType: challenge.frequencyType,
            scheduledWeekdays: challenge.scheduledWeekdays, durationDays: 14,
            proposedStartDate: challenge.startDate, challengeTimezone: challenge.challengeTimezone,
            dailyDeadlineMinutes: challenge.dailyDeadlineMinutes, recoveryDayAllowance: challenge.recoveryDayAllowance,
            votingStartsAt: now, votingEndsAt: now.addingTimeInterval(48 * 3_600),
            eligibleVoterIDs: Set(snapshot.memberships.filter { $0.groupID == group.id }.map(\.userID)),
            status: .voting, createdAt: now
        )
        let fromProposal = ChallengeFactory.makeChallenge(from: proposal, createdAt: now)
        #expect(fromProposal.title == challenge.title)
        #expect(fromProposal.endDate == challenge.endDate)
        #expect(fromProposal.status == .scheduled)
    }

    @Test func reconcileClearsStaleStreakWhenUserHasNoAcceptedCheckIns() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London") ?? .current
        // Friday afternoon after Mon–Thu lunch deadlines have passed.
        var components = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 8, day: 21, hour: 15, minute: 0)
        let now = calendar.date(from: components) ?? Date.now
        var snapshot = DemoSeed.make(now: now)
        let lunchChallenge = snapshot.challenges.first { $0.title == "Lunch Walk Round" }
        guard let challenge = lunchChallenge else {
            Issue.record("Missing Lunch Walk Round")
            return
        }
        guard let entryIndex = snapshot.leaderboard.firstIndex(where: {
            $0.challengeID == challenge.id && $0.user.id == snapshot.currentUser.id
        }) else {
            Issue.record("Missing Lunch Break leaderboard entry for current user")
            return
        }
        // Simulate the Session 2 bug: decorative streak with no submissions.
        snapshot.leaderboard[entryIndex].currentStreak = 3
        snapshot.leaderboard[entryIndex].longestStreak = 5
        snapshot.submissions.removeAll {
            $0.challengeID == challenge.id && $0.userID == snapshot.currentUser.id
        }
        snapshot.recoveryDays.removeAll {
            $0.challengeID == challenge.id && $0.userID == snapshot.currentUser.id
        }

        let cleared = RoundStateReconciler.reconcile(snapshot: snapshot, at: now)
        let clearedEntry = cleared.snapshot.leaderboard.first {
            $0.challengeID == challenge.id && $0.user.id == snapshot.currentUser.id
        }
        #expect(clearedEntry?.currentStreak == 0)

        let today = ScheduleEngine.requirementDay(for: now, challenge: challenge) ?? now
        var afterCheckIn = cleared.snapshot
        afterCheckIn.submissions.append(.init(
            id: UUID(), clientGeneratedID: UUID(), challengeID: challenge.id, userID: snapshot.currentUser.id,
            requirementDate: today, quantity: challenge.minimumQuantity, measurementType: challenge.measurementType,
            completedAt: now, submittedAt: now, syncState: .synced, verificationState: .accepted,
            createdAt: now, updatedAt: now
        ))
        let completed = RoundStateReconciler.reconcile(snapshot: afterCheckIn, at: now)
        let completedEntry = completed.snapshot.leaderboard.first {
            $0.challengeID == challenge.id && $0.user.id == snapshot.currentUser.id
        }
        #expect(completedEntry?.currentStreak == 1)
    }
}

struct MultiGroupAndRoutingTests {
    @Test func seededStandingsAreGroupScoped() {
        let snapshot = DemoSeed.make()
        let groupIDs = Set(snapshot.leaderboard.compactMap(\.groupID))
        #expect(snapshot.groups.count >= 2)
        #expect(groupIDs.count >= 2)
    }

    @Test func parsesUniversalAndCustomInviteRoutes() {
        #expect(AppRoute.parse(URL(string: "https://invite.round.test/join/abc123")!, inviteHost: "invite.round.test") == .joinGroup(code: "ABC123"))
        #expect(AppRoute.parse(URL(string: "round://join/abc123")!, inviteHost: "invite.round.test") == .joinGroup(code: "ABC123"))
        #expect(AppRoute.parse(URL(string: "https://evil.test/join/abc123")!, inviteHost: "invite.round.test") == nil)
        #expect(AppRoute.parse(URL(string: "round://join/no")!, inviteHost: "invite.round.test") == nil)
        let groupID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        #expect(AppRoute.parse(URL(string: "round://log/\(groupID.uuidString)")!, inviteHost: "invite.round.test") == .logWorkout(groupID: groupID))
        #expect(AppRoute.parse(URL(string: "https://invite.round.test/log/\(groupID.uuidString)")!, inviteHost: "invite.round.test") == .logWorkout(groupID: groupID))
    }
}

struct NotificationPlanningTests {
    @Test func plansAcrossGroupsAndCapsRequests() {
        let now = Date.now
        let snapshot = DemoSeed.make(now: now)
        let plan = NotificationPlanBuilder.build(snapshot: snapshot, now: now, maximumCount: 4)
        #expect(plan.count <= 4)
        #expect(Set(plan.map(\.groupID)).isSubset(of: Set(snapshot.groups.map(\.id))))
        #expect(plan.allSatisfy { $0.fireDate > now })
    }

    @Test func completedRequirementSuppressesIncompleteWarningsForThatDay() {
        let now = Date.now
        var snapshot = DemoSeed.make(now: now)
        let challenge = snapshot.challenges[0]
        let day = ScheduleEngine.requirementDay(for: now, challenge: challenge) ?? now
        snapshot.submissions.append(.init(
            id: UUID(), clientGeneratedID: UUID(), challengeID: challenge.id, userID: snapshot.currentUser.id,
            requirementDate: day, quantity: challenge.minimumQuantity, measurementType: challenge.measurementType,
            completedAt: now, submittedAt: now, syncState: .synced, verificationState: .accepted,
            createdAt: now, updatedAt: now
        ))
        let plan = NotificationPlanBuilder.build(snapshot: snapshot, now: now)
        #expect(!plan.contains {
            $0.challengeID == challenge.id && ($0.kind == .evening || $0.kind == .deadline) &&
            ScheduleEngine.isSameRequirementDay($0.fireDate, day, challenge: challenge)
        })
    }
}

@MainActor
private final class AcceptingRepository: AppRepository {
    var mode: AppMode = .demo
    var savedSnapshots: [DemoSnapshot] = []
    func load() async throws -> DemoSnapshot { DemoSeed.make() }
    func save(_ snapshot: DemoSnapshot) async throws { savedSnapshots.append(snapshot) }
    func reset() async throws -> DemoSnapshot { DemoSeed.make() }
    func syncSubmission(_ submission: Submission) async -> SubmissionSyncResult {
        .accepted(.init(submissionID: submission.id, acceptedAt: .now))
    }
    func perform(_ command: RepositoryCommand) async throws -> DemoSnapshot? {
        let current = try await load()
        let (updated, _) = try SnapshotCommandApplier.apply(command, to: current)
        try await save(updated)
        return updated
    }
    func requestClipUploadURL(groupID: UUID, challengeID: UUID, requirementDate: Date, clipID: UUID) async throws -> ClipUploadTicket {
        ClipUploadTicket(storagePath: "test/\(clipID.uuidString).mov", uploadURL: URL(fileURLWithPath: "/dev/null"), token: nil, clipID: clipID)
    }
    func uploadClip(ticket: ClipUploadTicket, fileURL: URL) async throws {}
}

@MainActor
private final class RetryingRepository: AppRepository {
    var mode: AppMode = .demo
    var syncCount = 0
    func load() async throws -> DemoSnapshot { DemoSeed.make() }
    func save(_ snapshot: DemoSnapshot) async throws {}
    func reset() async throws -> DemoSnapshot { DemoSeed.make() }
    func syncSubmission(_ submission: Submission) async -> SubmissionSyncResult {
        syncCount += 1
        return .retryable("Temporary connection problem", retryAfter: nil)
    }
    func perform(_ command: RepositoryCommand) async throws -> DemoSnapshot? { nil }
    func requestClipUploadURL(groupID: UUID, challengeID: UUID, requirementDate: Date, clipID: UUID) async throws -> ClipUploadTicket {
        ClipUploadTicket(storagePath: "test/\(clipID.uuidString).mov", uploadURL: URL(fileURLWithPath: "/dev/null"), token: nil, clipID: clipID)
    }
    func uploadClip(ticket: ClipUploadTicket, fileURL: URL) async throws {}
}

struct OfflineSyncTests {
    @MainActor
    @Test func acceptedSubmissionDrainsIdempotently() async {
        let now = Date.now
        let repository = AcceptingRepository()
        let coordinator = OfflineSyncCoordinator(repository: repository, clock: FixedAppClock(now: now))
        var snapshot = SnapshotMigrator.migrate(DemoSeed.make(now: now, includePendingSubmission: true))
        guard let operation = snapshot.pendingOperations.first else {
            Issue.record("Missing pending operation")
            return
        }
        let submission = snapshot.submissions.first { $0.clientGeneratedID == operation.clientGeneratedID }
        let baselinePoints = snapshot.leaderboard.first {
            $0.user.id == submission?.userID && $0.challengeID == submission?.challengeID
        }?.points ?? 0
        snapshot.pendingOperations[0].nextRetryAt = now
        let first = await coordinator.drain(snapshot, connected: true)
        let second = await coordinator.drain(first, connected: true)
        #expect(first.pendingOperations.isEmpty)
        #expect(first.submissions.first { $0.clientGeneratedID == operation.clientGeneratedID }?.syncState == .synced)
        #expect(second.scoreEvents.count == first.scoreEvents.count)
        if let submission,
           let challenge = first.challenges.first(where: { $0.id == submission.challengeID }),
           let entry = first.leaderboard.first(where: { $0.user.id == submission.userID && $0.challengeID == submission.challengeID }) {
            let acceptedPoints = ScoringEngine.points(completedQuantity: submission.quantity, minimumQuantity: challenge.minimumQuantity)
            let ledgerPoints = first.scoreEvents.filter {
                $0.challengeID == challenge.id && $0.userID == submission.userID
            }.reduce(0) { $0 + $1.points }
            #expect(entry.points == baselinePoints + acceptedPoints)
            #expect(entry.points == ledgerPoints)
        }
    }

    @MainActor
    @Test func transientFailuresUseBackoffThenRequireManualRetry() async {
        let now = Date.now
        let repository = RetryingRepository()
        let coordinator = OfflineSyncCoordinator(repository: repository, clock: FixedAppClock(now: now))
        var snapshot = SnapshotMigrator.migrate(DemoSeed.make(now: now, includePendingSubmission: true))
        guard let clientID = snapshot.pendingOperations.first?.clientGeneratedID else {
            Issue.record("Missing pending operation")
            return
        }
        snapshot.pendingOperations[0].retryCount = 0
        snapshot.pendingOperations[0].nextRetryAt = now
        let expectedDelays: [TimeInterval] = [5, 30, 120, 600, 1_800]

        for delay in expectedDelays {
            snapshot = await coordinator.drain(snapshot, connected: true, force: true)
            #expect(abs((snapshot.pendingOperations.first?.nextRetryAt.timeIntervalSince(now) ?? 0) - delay) < 0.01)
            #expect(snapshot.submissions.first { $0.clientGeneratedID == clientID }?.syncState == .waiting)
        }
        snapshot = await coordinator.drain(snapshot, connected: true, force: true)
        #expect(repository.syncCount == 6)
        #expect(snapshot.submissions.first { $0.clientGeneratedID == clientID }?.syncState == .failed)

        snapshot = coordinator.prepareManualRetry(snapshot, clientGeneratedID: clientID)
        #expect(snapshot.pendingOperations[0].retryCount == 0)
        #expect(snapshot.submissions.first { $0.clientGeneratedID == clientID }?.syncState == .waiting)
    }
}

// Serialized because the tests below script a shared URLProtocol stub.
@Suite(.serialized)
struct SupabaseTransportTests {
    @Test func supabaseEndpointKeepsQueryStringsUnescaped() throws {
        for base in ["https://project.supabase.co", "https://project.supabase.co/"] {
            let client = SupabaseClient(
                configuration: SupabaseConfiguration(url: URL(string: base)!, anonymousKey: "anon"),
                keychain: KeychainStore()
            )
            let grantTypes = ["password", "id_token", "refresh_token"]
            for grantType in grantTypes {
                let url = try client.endpoint(for: "/auth/v1/token?grant_type=\(grantType)")
                #expect(url.absoluteString == "https://project.supabase.co/auth/v1/token?grant_type=\(grantType)")
            }
            #expect(try client.endpoint(for: "/auth/v1/signup").absoluteString == "https://project.supabase.co/auth/v1/signup")
            #expect(try client.endpoint(for: "/functions/v1/app-snapshot").absoluteString == "https://project.supabase.co/functions/v1/app-snapshot")
            #expect(try client.endpoint(for: "/rest/v1/rpc/create_private_group").absoluteString == "https://project.supabase.co/rest/v1/rpc/create_private_group")
        }
    }

    @Test func freshTokenRejectionIsTreatedAsRetryableClockSkew() {
        // PostgREST rejects directly; app-snapshot re-wraps the same text in a 422 body.
        let retryable = [
            #"{"code":"PGRST301","message":"JWT issued at future"}"#,
            #"{"message":"JWT issued at future"}"#,
            #"{"message":"JWT issued in the future"}"#
        ]
        for payload in retryable {
            guard let message = SupabaseClient.errorMessage(in: Data(payload.utf8)) else {
                Issue.record("No message parsed from \(payload)")
                continue
            }
            #expect(SupabaseClient.indicatesUnsyncedClock(message))
        }

        let terminal = [
            #"{"message":"permission denied for function is_active_group_member"}"#,
            #"{"error_code":"invalid_credentials","msg":"Invalid login credentials"}"#,
            #"{"error_description":"Unsupported provider: provider is not enabled"}"#,
            #"{"message":"JWT expired"}"#
        ]
        for payload in terminal {
            guard let message = SupabaseClient.errorMessage(in: Data(payload.utf8)) else {
                Issue.record("No message parsed from \(payload)")
                continue
            }
            #expect(!SupabaseClient.indicatesUnsyncedClock(message))
        }

        #expect(SupabaseClient.errorMessage(in: Data("404 page not found".utf8)) == nil)
    }

    @Test func clockSkewRejectionRetriesUntilTheTokenIsAccepted() async throws {
        StubURLProtocol.reset(with: [
            (422, #"{"message":"JWT issued at future"}"#),
            (422, #"{"message":"JWT issued at future"}"#),
            (200, #"{"schemaVersion":3}"#)
        ])
        let data = try await StubURLProtocol.makeClient().request(
            path: "/functions/v1/app-snapshot",
            requiresSession: false
        )
        #expect(String(decoding: data, as: UTF8.self) == #"{"schemaVersion":3}"#)
        #expect(StubURLProtocol.requestCount == 3)
    }

    @Test func clockSkewRetriesAreBoundedAndSurfaceTheError() async throws {
        StubURLProtocol.reset(with: [(422, #"{"message":"JWT issued at future"}"#)])
        await #expect(throws: RepositoryError.self) {
            try await StubURLProtocol.makeClient().request(
                path: "/functions/v1/app-snapshot",
                requiresSession: false
            )
        }
        #expect(StubURLProtocol.requestCount == 4)
    }

    @Test func realFailuresAreNotRetried() async throws {
        StubURLProtocol.reset(with: [(422, #"{"message":"permission denied for function is_active_group_member"}"#)])
        await #expect(throws: RepositoryError.self) {
            try await StubURLProtocol.makeClient().request(
                path: "/functions/v1/app-snapshot",
                requiresSession: false
            )
        }
        #expect(StubURLProtocol.requestCount == 1)
    }
}

struct BackendErrorCopyTests {
    @Test func enforcedRulesReachTheBannerAsSentences() {
        let owner = RepositoryError.server("transfer_ownership_required").localizedDescription
        #expect(owner == "You still own a group with other members. Make someone else the owner first.")
        #expect(!owner.contains("_"))

        for code in ["not_a_member", "not_allowed", "not_authenticated"] {
            #expect(!RepositoryError.server(code).localizedDescription.contains("_"))
        }
    }

    @Test func unrecognisedServerTextIsPassedThrough() {
        let message = "Round is temporarily unavailable."
        #expect(RepositoryError.server(message).localizedDescription == message)
    }
}

/// Replays a scripted sequence of responses; the last entry answers every further request.
final class StubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var responses: [(status: Int, body: String)] = []
    private static var count = 0

    static func reset(with responses: [(status: Int, body: String)]) {
        lock.withLock {
            self.responses = responses
            count = 0
        }
    }

    static var requestCount: Int { lock.withLock { count } }

    static func makeClient() -> SupabaseClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return SupabaseClient(
            configuration: SupabaseConfiguration(url: URL(string: "https://stub.supabase.co")!, anonymousKey: "anon"),
            keychain: KeychainStore(),
            session: URLSession(configuration: configuration)
        )
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let entry: (status: Int, body: String) = Self.lock.withLock {
            let entry = Self.responses[min(Self.count, Self.responses.count - 1)]
            Self.count += 1
            return entry
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: entry.status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(entry.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
