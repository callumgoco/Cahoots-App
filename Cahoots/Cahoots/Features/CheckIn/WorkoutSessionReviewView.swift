import SwiftUI

struct WorkoutSessionReviewView: View {
    @Bindable var controller: WorkoutSessionController
    let store: AppStore

    var body: some View {
        switch controller.phase {
        case .waitingForFinish:
            waitingForFinish
        case .review:
            review
        default:
            EmptyView()
        }
    }

    private var review: some View {
        VStack(spacing: AppSpacing.large) {
            if let previewURL = controller.previewURL, FileManager.default.fileExists(atPath: previewURL.path) {
                VideoPlayerRepresentable(url: previewURL)
                    .frame(maxWidth: .infinity)
                    .frame(height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .fill(AppColors.card)
                    .frame(maxWidth: .infinity)
                    .frame(height: 360)
                    .overlay {
                        VStack(spacing: AppSpacing.small) {
                            Image(systemName: "video.slash")
                                .font(.largeTitle)
                                .foregroundStyle(AppColors.secondaryInk)
                            Text("Preview unavailable")
                                .font(.headline)
                            Text("Your clip is saved. You can still use it for this check-in.")
                                .font(.subheadline)
                                .foregroundStyle(AppColors.secondaryInk)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, AppSpacing.large)
                        }
                        .environment(\.colorScheme, .dark)
                        .foregroundStyle(AppColors.ink)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Preview unavailable")
            }
            Text(controller.clipDurationLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.secondaryInk)
            if let formError = controller.formError {
                Label(formError, systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(AppColors.danger)
            }
            Spacer()
            Button("Use this clip") { controller.acceptCurrentClip(store: store) }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!(controller.recordedClips.last.map { $0.durationSeconds >= WorkoutClipRules.minimumDuration } ?? false))
                .accessibilityIdentifier("workoutSession.useClip")
            Button("Retake") { controller.retake() }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("workoutSession.retake")
        }
        .padding(AppSpacing.page)
        .roundPage()
    }

    private var waitingForFinish: some View {
        VStack(spacing: AppSpacing.extraLarge) {
            Image(systemName: "figure.walk")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(AppColors.accent)
                .accessibilityHidden(true)
            Text("Start clip saved")
                .font(.title2.bold())
            Text("Come back after your activity to record the finish clip and confirm today’s amount.")
                .multilineTextAlignment(.center)
                .foregroundStyle(AppColors.secondaryInk)
            Spacer()
            Button("Record finish clip") {
                controller.recordFinishClip(store: store)
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("workoutSession.recordFinish")
            Button("Discard start clip", role: .destructive) {
                controller.discardStartClip(store: store)
            }
            .frame(minHeight: 44)
        }
        .padding(AppSpacing.page)
        .roundPage()
    }
}
