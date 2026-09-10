import Foundation
import Testing
import UIKit
@testable import Cahoots

@MainActor
struct UIRemediationTests {
    @Test func defaultDemoHasNoPendingOrRejectedCheckIns() {
        let snapshot = DemoSeed.make()
        #expect(snapshot.pendingOperations.isEmpty)
        #expect(!snapshot.submissions.contains { $0.syncState == .waiting || $0.syncState == .failed || $0.syncState == .rejected })
        #expect(snapshot.submissions.contains { $0.userID != snapshot.currentUser.id })
    }

    @Test func proposalDraftsAreGroupScopedAndClearExplicitly() {
        let suite = "cahoots.tests.proposalDraft.\(UUID().uuidString)"
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

    @Test func colorThemesProvideDistinctLightAndDarkPalettes() {
        #expect(AppColorTheme.allCases.count == 7)
        for theme in AppColorTheme.allCases {
            let light = theme.palette(for: .light)
            let dark = theme.palette(for: .dark)
            #expect(light.page != dark.page || light.ink != dark.ink)
            #expect(light.ink != light.page)
            #expect(dark.ink != dark.page)
        }
        AppColorThemeBridge.current = .sky
        #expect(AppColorThemeBridge.current == .sky)
        AppColorThemeBridge.current = .mint
    }

    @Test func friendFacingSyncCopyAvoidsProvisionalLanguage() {
        #expect(FriendFacingCopy.syncLabel(for: .waiting) == "Saved on this phone")
        #expect(FriendFacingCopy.syncLabel(for: .failed) == "Saved on this phone")
        #expect(FriendFacingCopy.missedWindow == "Missed today’s window")
        #expect(!FriendFacingCopy.syncLabel(for: .waiting).localizedCaseInsensitiveContains("provisional"))
        #expect(FriendFacingCopy.syncExplanation(for: .waiting).localizedCaseInsensitiveContains("crew"))
        #expect(FriendFacingCopy.syncExplanation(for: .failed).localizedCaseInsensitiveContains("retry"))
    }

    @Test func weekStripMarksCompletedMissedAndRestDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let monday = calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 12))!
        let wednesday = calendar.date(byAdding: .day, value: 2, to: monday)!
        let challenge = CahootsChallenge(
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

    @Test func leaderboardListsSmallCrewsInsteadOfBlanking() {
        #expect(LeaderboardStandingsLayout.showsPodium(entryCount: 0, isAccessibilitySize: false) == false)
        #expect(LeaderboardStandingsLayout.showsPodium(entryCount: 2, isAccessibilitySize: false) == false)
        #expect(LeaderboardStandingsLayout.showsPodium(entryCount: 3, isAccessibilitySize: false))
        #expect(LeaderboardStandingsLayout.showsPodium(entryCount: 4, isAccessibilitySize: true) == false)

        #expect(LeaderboardStandingsLayout.showsDuel(entryCount: 2, isAccessibilitySize: false))
        #expect(LeaderboardStandingsLayout.showsDuel(entryCount: 2, isAccessibilitySize: true) == false)
        #expect(LeaderboardStandingsLayout.showsDuel(entryCount: 3, isAccessibilitySize: false) == false)

        let two = ["a", "b"]
        #expect(LeaderboardStandingsLayout.listEntries(from: two, showPodium: false) == two)
        #expect(LeaderboardStandingsLayout.listEntries(from: two, showPodium: true).isEmpty)
        #expect(LeaderboardStandingsLayout.listEntries(from: two, showPodium: false, showDuel: true).isEmpty)

        let four = ["a", "b", "c", "d"]
        #expect(LeaderboardStandingsLayout.listEntries(from: four, showPodium: true) == ["d"])
        #expect(LeaderboardStandingsLayout.listEntries(from: four, showPodium: false) == four)
    }

    @Test func todayCrewStatusBuilderMarksDoneRestAndPending() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 12))!
        let challenge = CahootsChallenge(
            id: UUID(), groupID: UUID(), proposalID: nil, title: "Test", activityType: "push-ups",
            measurementType: .repetitions, minimumQuantity: 15, frequencyType: .daily,
            scheduledWeekdays: [], timesPerWeek: nil, startDate: day.addingTimeInterval(-5 * 86_400),
            endDate: day.addingTimeInterval(10 * 86_400), challengeTimezone: "UTC",
            dailyDeadlineMinutes: 23 * 60, recoveryDayAllowance: 2, status: .active, scoringVersion: 1, createdAt: day
        )
        let you = CahootsUser(
            id: UUID(), appleSubjectID: nil, displayName: "You", avatarPath: nil,
            timezoneIdentifier: "UTC", createdAt: day, updatedAt: day, deletedAt: nil, showsExactTotals: true
        )
        let donePeer = CahootsUser(
            id: UUID(), appleSubjectID: nil, displayName: "Done Peer", avatarPath: nil,
            timezoneIdentifier: "UTC", createdAt: day, updatedAt: day, deletedAt: nil, showsExactTotals: true
        )
        let restPeer = CahootsUser(
            id: UUID(), appleSubjectID: nil, displayName: "Rest Peer", avatarPath: nil,
            timezoneIdentifier: "UTC", createdAt: day, updatedAt: day, deletedAt: nil, showsExactTotals: true
        )
        let pendingPeer = CahootsUser(
            id: UUID(), appleSubjectID: nil, displayName: "Pending Peer", avatarPath: nil,
            timezoneIdentifier: "UTC", createdAt: day, updatedAt: day, deletedAt: nil, showsExactTotals: true
        )
        let submission = Submission(
            id: UUID(), clientGeneratedID: UUID(), challengeID: challenge.id, userID: donePeer.id,
            requirementDate: day, quantity: 15, measurementType: .repetitions, completedAt: day,
            submittedAt: day, syncState: .synced, verificationState: .accepted, createdAt: day, updatedAt: day
        )
        let recovery = RecoveryDayUsage(
            id: UUID(), challengeID: challenge.id, userID: restPeer.id, requirementDate: day, createdAt: day
        )

        let statuses = TodayCrewStatusBuilder.statuses(
            members: [pendingPeer, restPeer, donePeer, you],
            submissions: [submission],
            recoveries: [recovery],
            challenge: challenge,
            now: day,
            currentUserID: you.id
        )

        #expect(statuses.count == 4)
        #expect(statuses.first?.isCurrentUser == true)
        #expect(statuses.first(where: { $0.user.id == donePeer.id })?.status == .done)
        #expect(statuses.first(where: { $0.user.id == restPeer.id })?.status == .rest)
        #expect(statuses.first(where: { $0.user.id == pendingPeer.id })?.status == .pending)
        #expect(statuses.first(where: { $0.user.id == you.id })?.status == .pending)
    }

    @Test func roundProgressReportsDayOfSchedule() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 12))!
        let challenge = CahootsChallenge(
            id: UUID(), groupID: UUID(), proposalID: nil, title: "Test", activityType: "push-ups",
            measurementType: .repetitions, minimumQuantity: 15, frequencyType: .daily,
            scheduledWeekdays: [], timesPerWeek: nil, startDate: start,
            endDate: start.addingTimeInterval(29 * 86_400), challengeTimezone: "UTC",
            dailyDeadlineMinutes: 23 * 60, recoveryDayAllowance: 1, status: .active, scoringVersion: 1, createdAt: start
        )
        let day10 = calendar.date(byAdding: .day, value: 9, to: start)!
        let progress = RoundProgress.dayOfRound(challenge: challenge, now: day10)
        #expect(progress?.current == 10)
        #expect(progress?.total == 30)
        #expect(RoundProgress.dayLabel(challenge: challenge, now: day10) == "Day 10 of 30")
    }
}
