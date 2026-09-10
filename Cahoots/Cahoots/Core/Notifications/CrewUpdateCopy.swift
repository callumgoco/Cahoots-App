import Foundation

/// Lock-screen / push copy for crew-wide vote and round events (no quantities).
enum CrewUpdateCopy {
    static func voteOpenedTitle(groupName: String) -> String {
        groupName
    }

    static func voteOpenedBody(actorName: String) -> String {
        String(localized: "\(actorName) opened a group vote. Review it before it closes.")
    }

    static func roundStartedTitle(groupName: String) -> String {
        groupName
    }

    static func roundStartedBody(title: String) -> String {
        String(localized: "\(title) has started. Check in on Today when you’re ready.")
    }

    static func roundScheduledBody(title: String, startDate: Date) -> String {
        let when = startDate.formatted(date: .abbreviated, time: .omitted)
        return String(localized: "\(title) is scheduled to start \(when).")
    }

    static func proposalPassedScheduledBody(title: String, startDate: Date) -> String {
        let when = startDate.formatted(date: .abbreviated, time: .omitted)
        return String(localized: "The crew accepted \(title). It starts \(when).")
    }

    static func proposalPassedActiveBody(title: String) -> String {
        String(localized: "The crew accepted \(title). The round is live.")
    }

    static func roundStartingLocalTitle() -> String {
        String(localized: "Your next round starts soon")
    }

    static func roundStartingLocalBody(title: String) -> String {
        String(localized: "\(title) begins today. Open Today to get ready.")
    }

    static func voteOpenedLocalTitle() -> String {
        String(localized: "A group vote is open")
    }

    static func voteOpenedLocalBody() -> String {
        String(localized: "Your crew needs your vote before the proposal closes.")
    }
}
