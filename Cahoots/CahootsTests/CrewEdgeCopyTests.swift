import Foundation
import Testing
@testable import Cahoots

struct CrewEdgeCopyTests {
    @Test func emptyTodayFramingDependsOnCrewSizeAndFailedVote() {
        #expect(CrewEdgeCopy.emptyTodayTitle(memberCount: 1, hasFailedProposal: false) == "Invite your crew")
        #expect(CrewEdgeCopy.emptyTodayMessage(memberCount: 1, hasFailedProposal: false)
            .localizedCaseInsensitiveContains("invite"))
        #expect(CrewEdgeCopy.emptyTodayTitle(memberCount: 3, hasFailedProposal: false) == "No active round")
        #expect(CrewEdgeCopy.emptyTodayTitle(memberCount: 3, hasFailedProposal: true) == "Ready for another try")
        #expect(CrewEdgeCopy.emptyTodayMessage(memberCount: 2, hasFailedProposal: true)
            .localizedCaseInsensitiveContains("didn’t pass")
            || CrewEdgeCopy.emptyTodayMessage(memberCount: 2, hasFailedProposal: true)
            .localizedCaseInsensitiveContains("didn't pass"))
    }

    @Test func failedVoteCopyPointsToNextSteps() {
        #expect(CrewEdgeCopy.failedVoteHeadline == "Proposal did not pass")
        #expect(CrewEdgeCopy.failedVoteBody.localizedCaseInsensitiveContains("duplicate"))
        #expect(CrewEdgeCopy.failedCrewCardSubtitle.localizedCaseInsensitiveContains("did not pass"))
        #expect(CrewEdgeCopy.crewReadyToPropose.localizedCaseInsensitiveContains("vote"))
    }

    @Test func scheduledStartsLabelUsesRelativeHints() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 12))!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let today = calendar.startOfDay(for: now)
        let nextWeek = calendar.date(byAdding: .day, value: 5, to: today)!

        #expect(CrewEdgeCopy.scheduledStartsLabel(startDate: tomorrow, now: now)
            .localizedCaseInsensitiveContains("tomorrow"))
        #expect(CrewEdgeCopy.scheduledStartsLabel(startDate: today, now: now)
            .localizedCaseInsensitiveContains("today"))
        let later = CrewEdgeCopy.scheduledStartsLabel(startDate: nextWeek, now: now)
        #expect(later.localizedCaseInsensitiveContains("Starts"))
        #expect(!later.localizedCaseInsensitiveContains("tomorrow"))
    }

    @Test func scheduledSupportingCopyIncludesDuration() {
        let copy = CrewEdgeCopy.scheduledSupportingCopy(title: "push-ups", durationDays: 30)
        #expect(copy.localizedCaseInsensitiveContains("push-ups"))
        #expect(copy.contains("30"))
        #expect(copy.localizedCaseInsensitiveContains("check-in"))
    }
}
