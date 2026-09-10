import SwiftUI

struct ChallengeDetailsView: View {
    let challenge: CahootsChallenge

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.large) {
                CahootsCard(elevated: true) {
                    VStack(alignment: .leading, spacing: AppSpacing.medium) {
                        StatusPill(text: challenge.status.rawValue.capitalized, kind: .positive)
                        Text(challenge.title).font(.largeTitle.bold())
                        AdaptiveStack(spacing: AppSpacing.small) {
                            Text(challenge.quantityLabel).font(AppTypography.heroMetric)
                            Text(challenge.activityType).font(.title3.bold())
                        }
                    }
                }
                CahootsCard {
                    VStack(alignment: .leading, spacing: AppSpacing.medium) {
                        CahootsSectionHeader(title: "Schedule")
                        detailRow("Starts", challenge.startDate.formatted(date: .long, time: .omitted))
                        detailRow("Ends", challenge.endDate.formatted(date: .long, time: .omitted))
                        detailRow("Days", challenge.frequencyType == .daily ? "Every day" : "Selected weekdays")
                    }
                }
                CahootsCard {
                    VStack(alignment: .leading, spacing: AppSpacing.medium) {
                        CahootsSectionHeader(title: "Rules")
                        detailRow("Daily deadline", deadlineLabel)
                        detailRow("Timezone", challenge.challengeTimezone.replacingOccurrences(of: "_", with: " "))
                        detailRow("Recovery allowance", "\(challenge.recoveryDayAllowance)")
                    }
                }
            }
            .padding(AppSpacing.page)
        }
        .navigationTitle("Challenge details")
        .navigationBarTitleDisplayMode(.inline)
        .roundPage()
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(AppColors.secondaryInk)
            Spacer()
            Text(value).font(.body.weight(.semibold)).multilineTextAlignment(.trailing)
        }
    }

    private var deadlineLabel: String {
        let hour = challenge.dailyDeadlineMinutes / 60
        let minute = challenge.dailyDeadlineMinutes % 60
        return DateComponents(calendar: .current, hour: hour, minute: minute).date?.formatted(date: .omitted, time: .shortened) ?? "—"
    }
}
