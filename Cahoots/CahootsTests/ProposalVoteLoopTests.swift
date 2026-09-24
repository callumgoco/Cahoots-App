import Foundation
import Testing
@testable import Cahoots

@MainActor
private final class MutableDemoRepository: AppRepository {
    var mode: AppMode = .demo
    var snapshot: DemoSnapshot

    init(snapshot: DemoSnapshot) {
        self.snapshot = snapshot
    }

    func load() async throws -> DemoSnapshot { snapshot }
    func save(_ snapshot: DemoSnapshot) async throws { self.snapshot = snapshot }
    func reset() async throws -> DemoSnapshot { snapshot }

    func syncSubmission(_ submission: Submission, challengeTimezone: String) async -> SubmissionSyncResult {
        .accepted(.init(submissionID: submission.id, acceptedAt: .now))
    }

    func perform(_ command: RepositoryCommand) async throws -> DemoSnapshot? {
        let (updated, _) = try SnapshotCommandApplier.apply(command, to: snapshot, now: .now)
        snapshot = updated
        return updated
    }

    func requestClipUploadURL(groupID: UUID, challengeID: UUID, requirementDateToken: String, clipID: UUID) async throws -> ClipUploadTicket {
        ClipUploadTicket(
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

@MainActor
struct ProposalVoteLoopTests {
    @Test func createProposalAutoAcceptsAndOpensVote() async {
        var seed = DemoSeed.make()
        let openIDs = Set(seed.proposals.filter { $0.status == .voting }.map(\.id))
        seed.proposals.removeAll { openIDs.contains($0.id) }
        seed.votes.removeAll { openIDs.contains($0.proposalID) }
        seed.challenges.removeAll { $0.status == .scheduled }

        let repository = MutableDemoRepository(snapshot: seed)
        let clock = FixedAppClock(now: .now)
        let environment = AppEnvironment(
            repository: repository,
            notifications: NotificationService(),
            entitlements: FreeEntitlementService(),
            network: NetworkMonitor(),
            keychain: KeychainStore(),
            authService: nil,
            clock: clock,
            syncCoordinator: OfflineSyncCoordinator(repository: repository, clock: clock)
        )
        let store = AppStore(environment: environment)
        store.snapshot = seed
        store.setActiveGroup(seed.groups.first?.id)
        store.hasCompletedOnboarding = true
        store.isSignedIn = true
        store.loadState = .loaded

        var draft = ProposalDraft()
        draft.title = "Wave One Round"
        draft.startDate = store.earliestProposalStartDate
        draft.deadlineMinutes = 23 * 60 + 59

        let ok = await store.createProposal(from: draft)
        #expect(ok)
        #expect(store.currentProposal != nil)
        #expect(store.presentOpenVote)
        #expect(store.selectedTab == 1)
        let myVote = store.snapshot?.votes.first {
            $0.proposalID == store.currentProposal?.id && $0.userID == store.currentUser?.id
        }
        #expect(myVote?.choice == .accept)
    }

    @Test func createProposalRejectsSoloCrew() async {
        var seed = DemoSeed.make()
        guard let groupID = seed.groups.first?.id else {
            Issue.record("Demo seed missing group")
            return
        }
        let userID = seed.currentUser.id
        seed.memberships.removeAll { $0.groupID == groupID && $0.userID != userID }
        seed.proposals.removeAll { $0.groupID == groupID && $0.status == .voting }
        seed.challenges.removeAll { $0.groupID == groupID && $0.status == .scheduled }

        let repository = MutableDemoRepository(snapshot: seed)
        let clock = FixedAppClock(now: .now)
        let environment = AppEnvironment(
            repository: repository,
            notifications: NotificationService(),
            entitlements: FreeEntitlementService(),
            network: NetworkMonitor(),
            keychain: KeychainStore(),
            authService: nil,
            clock: clock,
            syncCoordinator: OfflineSyncCoordinator(repository: repository, clock: clock)
        )
        let store = AppStore(environment: environment)
        store.snapshot = seed
        store.setActiveGroup(groupID)
        store.hasCompletedOnboarding = true
        store.isSignedIn = true
        store.loadState = .loaded

        let ok = await store.createProposal(from: ProposalDraft())
        #expect(!ok)
        #expect(store.currentProposal == nil)
        #expect(!store.presentOpenVote)
        #expect(store.errorBanner == VotingWindowCopy.soloVoteDisabledHint)
    }
}
