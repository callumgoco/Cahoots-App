import Foundation

/// Copy for empty / invite / failed-vote / scheduled-round edge states.
enum CrewEdgeCopy {
    static func emptyTodayTitle(memberCount: Int, hasFailedProposal: Bool) -> String {
        if hasFailedProposal {
            return String(localized: "Ready for another try")
        }
        if memberCount < 2 {
            return String(localized: "Invite your crew")
        }
        return String(localized: "No active round")
    }

    static func emptyTodayMessage(memberCount: Int, hasFailedProposal: Bool) -> String {
        if hasFailedProposal {
            return String(localized: "The last proposal didn’t pass. Duplicate it, or start a fresh round whenever you’re ready.")
        }
        if memberCount < 2 {
            return String(localized: "You’re the only member so far. Invite friends, then start a round together — or begin solo with Start now.")
        }
        return String(localized: "Start a round with your crew and check in here each day.")
    }

    static var crewReadyToPropose: String {
        String(localized: "Your crew has enough people to vote. Start a round whenever you’re ready.")
    }

    static var failedVoteHeadline: String {
        String(localized: "Proposal did not pass")
    }

    static var failedVoteBody: String {
        String(localized: "Duplicate and edit for another vote, or start a fresh round. You can also invite more friends first.")
    }

    static var failedCrewCardSubtitle: String {
        String(localized: "Did not pass · Duplicate or start a new round")
    }

    static func scheduledStartsLabel(startDate: Date, now: Date = .now) -> String {
        let absolute = startDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: startDate)
        let today = calendar.startOfDay(for: now)
        let dayDelta = calendar.dateComponents([.day], from: today, to: startDay).day
        if dayDelta == 1 {
            return String(localized: "Starts tomorrow · \(absolute)")
        }
        if dayDelta == 0 {
            return String(localized: "Starts today · \(absolute)")
        }
        let relative = startDate.formatted(.relative(presentation: .named, unitsStyle: .wide))
        return String(localized: "Starts \(absolute) (\(relative))")
    }

    static func scheduledSupportingCopy(title: String, durationDays: Int) -> String {
        String(localized: "\(title) · \(durationDays) days. Check-ins open when the round begins.")
    }
}
