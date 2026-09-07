import Foundation
import Testing
@testable import Pact

@MainActor
struct UIRemediationTests {
    @Test func defaultDemoHasNoPendingOrRejectedCheckIns() {
        let snapshot = DemoSeed.make()
        #expect(snapshot.pendingOperations.isEmpty)
        #expect(!snapshot.submissions.contains { $0.syncState == .waiting || $0.syncState == .failed || $0.syncState == .rejected })
        #expect(snapshot.submissions.contains { $0.userID != snapshot.currentUser.id })
    }

    @Test func proposalDraftsAreGroupScopedAndClearExplicitly() {
        let suite = "round.tests.proposalDraft.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ProposalDraftStore(defaults: defaults)
        let userID = UUID()
        let firstGroupID = UUID()
        let secondGroupID = UUID()
        var first = ProposalDraft()
        first.title = "First group round"
        var second = ProposalDraft()
        second.title = "Second group round"

        store.save(first, userID: userID, groupID: firstGroupID)
        store.save(second, userID: userID, groupID: secondGroupID)

        #expect(store.load(userID: userID, groupID: firstGroupID)?.title == first.title)
        #expect(store.load(userID: userID, groupID: secondGroupID)?.title == second.title)
        store.clear(userID: userID, groupID: firstGroupID)
        #expect(store.load(userID: userID, groupID: firstGroupID) == nil)
        #expect(store.load(userID: userID, groupID: secondGroupID)?.title == second.title)
    }

    @Test func avatarMarksAreStableForTheSameUser() {
        let userID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let first = AvatarMark.forUser(userID)
        let second = AvatarMark.forUser(userID)
        #expect(first == second)
        let otherIDs = [
            UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
        ]
        #expect(otherIDs.contains { AvatarMark.forUser($0) != first || AvatarMark.paletteColor(for: $0) != AvatarMark.paletteColor(for: userID) })
    }

    @Test func friendFacingSyncCopyAvoidsProvisionalLanguage() {
        #expect(FriendFacingCopy.syncLabel(for: .waiting) == "Saved on this phone")
        #expect(FriendFacingCopy.syncLabel(for: .failed) == "Saved on this phone")
        #expect(FriendFacingCopy.missedWindow == "Missed today’s window")
        #expect(!FriendFacingCopy.syncLabel(for: .waiting).localizedCaseInsensitiveContains("provisional"))
    }

    @Test func weekStripMarksCompletedMissedAndRestDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let monday = calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 12))!
        let wednesday = calendar.date(byAdding: .day, value: 2, to: monday)!
        let challenge = RoundChallenge(
            id: UUID(), groupID: UUID(), proposalID: nil, title: "Test", activityType: "push-ups",
            measurementType: .repetitions, minimumQuantity: 15, frequencyType: .selectedWeekdays,
            scheduledWeekdays: [2, 4, 6], timesPerWeek: nil, startDate: monday,
            endDate: monday.addingTimeInterval(14 * 86_400), challengeTimezone: "UTC",
            dailyDeadlineMinutes: 12 * 60, recoveryDayAllowance: 1, status: .active, scoringVersion: 1, createdAt: monday
        )
        let userID = UUID()
        let submission = Submission(
            id: UUID(), clientGeneratedID: UUID(), challengeID: challenge.id, userID: userID,
            requirementDate: monday, quantity: 15, measurementType: .repetitions, completedAt: monday,
            submittedAt: monday, syncState: .synced, verificationState: .accepted, createdAt: monday, updatedAt: monday
        )
        let tokens = WeekStripBuilder.tokens(
            challenge: challenge,
            userID: userID,
            submissions: [submission],
            recoveries: [],
            now: wednesday
        )
        #expect(tokens.count == 7)
        #expect(tokens[0].state == .done)
        #expect(tokens[1].state == .rest)
        #expect(tokens[2].state == .today)
        #expect(tokens[3].state == .rest || tokens[3].state == .upcoming)
    }
}
