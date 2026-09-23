import Foundation

enum VotingWindowCopy {
    static let openDurationHours = 48

    /// Estimated close time used on the builder review step before a vote exists.
    static func estimatedCloseDate(from now: Date = .now) -> Date {
        now.addingTimeInterval(TimeInterval(openDurationHours) * 3_600)
    }

    static func reviewFootnote(canPutToVote: Bool, closesAt: Date) -> String {
        if canPutToVote {
            let when = closesAt.formatted(date: .abbreviated, time: .shortened)
            return String(localized: "Start now schedules the round immediately. Put to vote opens a 48-hour group vote (closes \(when)) that needs a strict majority.")
        }
        return String(localized: "Start now schedules the round immediately. Voting needs at least 2 crew members — invite friends from Crew, then put a round to vote.")
    }

    static var soloVoteDisabledHint: String {
        String(localized: "Voting needs at least 2 crew members. Start now, or invite friends from Crew.")
    }

    static func startNowCaption(startDate: Date, now: Date = .now, timeZoneIdentifier: String) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        if calendar.isDate(startDate, inSameDayAs: now) {
            return String(localized: "Check-ins start today")
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
           calendar.isDate(startDate, inSameDayAs: tomorrow) {
            return String(localized: "Check-ins start tomorrow")
        }
        let absolute = startDate.formatted(date: .abbreviated, time: .omitted)
        return String(localized: "Check-ins start \(absolute)")
    }

    static func putToVoteCaption(closesAt: Date) -> String {
        let when = closesAt.formatted(date: .abbreviated, time: .shortened)
        return String(localized: "Crew votes until \(when)")
    }

    /// Absolute close time plus relative remaining, e.g. "Closes 12 Sep, 7:30 pm (in 47 hours)".
    static func statusLine(endsAt: Date, now: Date = .now) -> String {
        if endsAt <= now { return String(localized: "Voting closed") }
        let absolute = endsAt.formatted(date: .abbreviated, time: .shortened)
        let relative = endsAt.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
        return String(localized: "Closes \(absolute) (\(relative))")
    }
}
