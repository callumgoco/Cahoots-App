import Foundation

struct ProposalDraft: Codable, Hashable, Sendable {
    var title = "30-Day Challenge"
    var activityName = "push-ups"
    var measurementType: MeasurementType = .repetitions
    var minimumQuantity: Double = 15
    var frequencyType: FrequencyType = .daily
    var scheduledWeekdays: Set<Int> = Set(1...7)
    var durationDays = 30
    var startDate = Calendar.current.startOfDay(for: .now)
    var deadlineMinutes = 21 * 60
    var timezone = TimeZone.current.identifier
    var recoveryDays = 1

    init() {}

    init(proposal: ChallengeProposal, earliestStartDate: Date) {
        title = proposal.title
        activityName = proposal.activityType
        measurementType = proposal.measurementType
        minimumQuantity = proposal.minimumQuantity
        frequencyType = proposal.frequencyType
        scheduledWeekdays = proposal.scheduledWeekdays
        durationDays = proposal.durationDays
        startDate = max(proposal.proposedStartDate, earliestStartDate)
        deadlineMinutes = proposal.dailyDeadlineMinutes
        timezone = proposal.challengeTimezone
        recoveryDays = proposal.recoveryDayAllowance
    }
}
