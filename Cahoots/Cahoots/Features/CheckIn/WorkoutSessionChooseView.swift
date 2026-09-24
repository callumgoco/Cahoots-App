import SwiftUI

struct WorkoutSessionChooseView: View {
    @Bindable var controller: WorkoutSessionController
    let store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                if let challenge = store.currentChallenge {
                    requirementsCard(challenge)
                }

                if !store.todayMemberStatuses.isEmpty {
                    CrewTodayStatusRail(
                        entries: store.todayMemberStatuses,
                        accessibilityID: "workoutSession.crewStatus"
                    )
                }

                if let personalRankLine {
                    Text(personalRankLine)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("workoutSession.personalRank")
                }
            }
            .padding(.horizontal, AppSpacing.page)
            .padding(.top, AppSpacing.medium)

            Spacer(minLength: AppSpacing.large)

            VStack(spacing: AppSpacing.medium) {
                if let formError = controller.formError {
                    Label(formError, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(AppColors.danger)
                        .font(.body.weight(.semibold))
                        .multilineTextAlignment(.center)
                }

                Button(controller.hasPendingStartClip
                       ? String(localized: "Record finish clip")
                       : String(localized: "Record")) {
                    controller.chooseRecord(store: store)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!controller.openedWhileWindowOpen)
                .accessibilityIdentifier("workoutSession.chooseRecord")

                Button("Skip recording") {
                    controller.skipRecording()
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!controller.openedWhileWindowOpen)
                .accessibilityIdentifier("workoutSession.skipRecording")
            }
            .padding(AppSpacing.page)
            .padding(.bottom, AppSpacing.medium)
        }
        .roundPage()
    }

    private func requirementsCard(_ challenge: CahootsChallenge) -> some View {
        CahootsCard(elevated: true) {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text("Today’s target")
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.secondaryInk)
                Text(challenge.quantityLabel)
                    .font(AppTypography.heroMetric)
                Text(challenge.activityType)
                    .font(.title3.bold())
                Text(chooseCopy(for: challenge))
                    .font(.subheadline)
                    .foregroundStyle(AppColors.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func chooseCopy(for challenge: CahootsChallenge) -> String {
        if controller.hasPendingStartClip {
            return String(localized: "Film a finish clip for the crew.")
        }
        if challenge.measurementType.requiresTwoClips {
            return String(localized: "A short clip now, and one when you finish.")
        }
        return String(localized: "A short clip for the crew.")
    }

    /// Own standing only. Peer points on this board already hide today’s score until reveal.
    private var personalRankLine: String? {
        guard let userID = store.currentUser?.id,
              let rank = store.currentRank,
              let entry = store.currentLeaderboard.first(where: { $0.user.id == userID }) else {
            return nil
        }
        return String(localized: "You’re \(Self.ordinal(rank)) · \(entry.points) pts")
    }

    private static func ordinal(_ rank: Int) -> String {
        let teen = rank % 100
        if (11...13).contains(teen) {
            return String(localized: "\(rank)th")
        }
        switch rank % 10 {
        case 1: return String(localized: "\(rank)st")
        case 2: return String(localized: "\(rank)nd")
        case 3: return String(localized: "\(rank)rd")
        default: return String(localized: "\(rank)th")
        }
    }
}
