import SwiftUI

struct WorkoutSessionChooseView: View {
    @Bindable var controller: WorkoutSessionController
    let store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: AppSpacing.medium) {
                if let challenge = store.currentChallenge {
                    VStack(spacing: AppSpacing.small) {
                        Text(challenge.activityType)
                            .font(.title2.bold())
                        Text("Target · \(challenge.quantityLabel)")
                            .foregroundStyle(AppColors.secondaryInk)
                        Text(chooseCopy(for: challenge))
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(AppColors.secondaryInk)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        String(
                            localized: "\(challenge.activityType). Target \(challenge.quantityLabel)"
                        )
                    )
                }

                if !store.todayPeerCheckIns.isEmpty {
                    WorkoutSessionCrewStrip(
                        store: store,
                        challenge: store.currentChallenge,
                        spoilered: !store.canRevealTodayQuantities
                    )
                }

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

    private func chooseCopy(for challenge: CahootsChallenge) -> String {
        if controller.hasPendingStartClip {
            return String(localized: "Film a finish clip for the crew, or skip and enter today’s amount only.")
        }
        if challenge.measurementType.requiresTwoClips {
            return String(localized: "Film short clips for the crew, or skip and enter today’s amount only. This round is honour system.")
        }
        return String(localized: "Film a short clip for the crew, or skip and enter today’s amount only. This round is honour system.")
    }
}
