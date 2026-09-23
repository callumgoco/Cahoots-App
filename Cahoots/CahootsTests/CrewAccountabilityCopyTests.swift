import Foundation
import Testing
@testable import Cahoots

struct CrewAccountabilityCopyTests {
    @Test func checkInSummaryNamesPendingPeers() {
        let you = makeUser("You", index: 1)
        let jordan = makeUser("Jordan Hale", index: 2)
        let sam = makeUser("Sam Lee", index: 3)
        let entries = [
            TodayMemberStatusEntry(user: you, status: .done, isCurrentUser: true),
            TodayMemberStatusEntry(user: jordan, status: .pending, isCurrentUser: false),
            TodayMemberStatusEntry(user: sam, status: .pending, isCurrentUser: false)
        ]
        let summary = CrewAccountabilityCopy.checkInSummary(entries: entries)
        #expect(summary == "1 of 3 done · Jordan and Sam still need to check in.")
        #expect(CrewAccountabilityCopy.stillNeedToCheckIn(entries: entries) == "Still need to: Jordan and Sam.")
    }

    @Test func checkInSummarySingularPeerNeedsToCheckIn() {
        let you = makeUser("You", index: 1)
        let alex = makeUser("Alex Tester", index: 2)
        let entries = [
            TodayMemberStatusEntry(user: you, status: .done, isCurrentUser: true),
            TodayMemberStatusEntry(user: alex, status: .pending, isCurrentUser: false)
        ]
        #expect(CrewAccountabilityCopy.checkInSummary(entries: entries) == "1 of 2 done · Alex still needs to check in.")
    }

    @Test func checkInSummaryWhenEveryoneIn() {
        let you = makeUser("You", index: 1)
        let jordan = makeUser("Jordan Hale", index: 2)
        let entries = [
            TodayMemberStatusEntry(user: you, status: .done, isCurrentUser: true),
            TodayMemberStatusEntry(user: jordan, status: .rest, isCurrentUser: false)
        ]
        #expect(CrewAccountabilityCopy.checkInSummary(entries: entries) == "Everyone’s in for today.")
        #expect(CrewAccountabilityCopy.stillNeedToCheckIn(entries: entries) == "Everyone else is in.")
    }

    @Test func voteSummaryHidesChoices() {
        let you = makeUser("Alex Chen", index: 1)
        let jordan = makeUser("Jordan Hale", index: 2)
        let sam = makeUser("Sam Lee", index: 3)
        let summary = CrewAccountabilityCopy.voteSummary(
            eligible: [you, jordan, sam],
            votedUserIDs: [you.id],
            currentUserID: you.id
        )
        #expect(summary == "1 of 3 voted · Jordan and Sam still need to vote.")
        #expect(!(summary?.localizedCaseInsensitiveContains("accept") ?? true))
        #expect(!(summary?.localizedCaseInsensitiveContains("reject") ?? true))
    }

    @Test func eveningNudgeScalesWithPendingPeers() {
        #expect(CrewAccountabilityCopy.eveningNudge(pendingOthers: 0) == "There is still time to check in today.")
        #expect(CrewAccountabilityCopy.eveningNudge(pendingOthers: 1) == "You and 1 other still need to check in.")
        #expect(CrewAccountabilityCopy.eveningNudge(pendingOthers: 3) == "You and 3 others still need to check in.")
    }

    @Test func afternoonSortEmphasizesPendingPeers() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 10))!
        let afternoon = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 16))!
        let challenge = CahootsChallenge(
            id: UUID(), groupID: UUID(), proposalID: nil, title: "Test", activityType: "push-ups",
            measurementType: .repetitions, minimumQuantity: 15, frequencyType: .daily,
            scheduledWeekdays: Set(1...7), timesPerWeek: nil, startDate: morning,
            endDate: morning.addingTimeInterval(10 * 86_400), challengeTimezone: "UTC",
            dailyDeadlineMinutes: 21 * 60, recoveryDayAllowance: 1, status: .active, scoringVersion: 1, createdAt: morning
        )
        let you = makeUser("You", index: 1)
        let done = makeUser("Done Peer", index: 2)
        let pending = makeUser("Pending Peer", index: 3)
        let submission = Submission(
            id: UUID(), clientGeneratedID: UUID(), challengeID: challenge.id, userID: done.id,
            requirementDate: calendar.startOfDay(for: morning), quantity: 15, measurementType: .repetitions,
            completedAt: morning, submittedAt: morning, syncState: .synced, verificationState: .accepted,
            createdAt: morning, updatedAt: morning
        )

        let morningOrder = TodayCrewStatusBuilder.statuses(
            members: [pending, done, you],
            submissions: [submission],
            recoveries: [],
            challenge: challenge,
            now: morning,
            currentUserID: you.id
        ).map(\.user.id)
        #expect(morningOrder.first == you.id)
        #expect(morningOrder[1] == done.id)
        #expect(morningOrder[2] == pending.id)

        let afternoonOrder = TodayCrewStatusBuilder.statuses(
            members: [pending, done, you],
            submissions: [submission],
            recoveries: [],
            challenge: challenge,
            now: afternoon,
            currentUserID: you.id
        ).map(\.user.id)
        #expect(afternoonOrder.first == you.id)
        #expect(afternoonOrder[1] == pending.id)
        #expect(afternoonOrder[2] == done.id)
    }

    private func makeUser(_ name: String, index: Int) -> CahootsUser {
        CahootsUser(
            id: UUID(uuidString: String(format: "aaaaaaaa-bbbb-cccc-dddd-%012d", index))!,
            appleSubjectID: nil,
            displayName: name,
            avatarPath: nil,
            timezoneIdentifier: "UTC",
            createdAt: .now,
            updatedAt: .now,
            deletedAt: nil,
            showsExactTotals: true
        )
    }
}
