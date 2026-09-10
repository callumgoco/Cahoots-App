import SwiftUI

struct WorkoutSessionPrepView: View {
    @Bindable var controller: WorkoutSessionController
    let store: AppStore
    let reduceMotion: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                flipCameraButton
            }
            .padding(.horizontal, AppSpacing.page)
            .padding(.top, AppSpacing.small)

            Spacer()

            VStack(spacing: AppSpacing.medium) {
                if let challenge = store.currentChallenge {
                    VStack(spacing: AppSpacing.small) {
                        Text(challenge.activityType)
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                        Text("Target · \(challenge.quantityLabel)")
                            .foregroundStyle(.white.opacity(0.72))
                        if challenge.measurementType.requiresTwoClips {
                            Text(controller.currentKind == .start
                                 ? String(localized: "Record a short start clip for the crew, then finish after your activity. You enter the minutes — this round is honour system.")
                                 : String(localized: "Record your finish clip for the crew. You enter the amount — this round is honour system."))
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white.opacity(0.72))
                        } else {
                            Text("A short clip for the crew. You enter the number — this round is honour system.")
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white.opacity(0.72))
                        }
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

                if !controller.isCaptureReady, controller.captureError == nil {
                    Label(String(localized: "Setting up camera…"), systemImage: "camera.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .accessibilityLabel(String(localized: "Setting up camera"))
                }

                if let captureError = controller.captureError {
                    Label(captureError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppColors.danger)
                        .font(.footnote.weight(.semibold))
                        .accessibilityLabel(String(localized: "Camera unavailable. \(captureError)"))
                }

                if !controller.openedWhileWindowOpen, let formError = controller.formError {
                    Label(formError, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(AppColors.danger)
                        .font(.body.weight(.semibold))
                        .multilineTextAlignment(.center)
                }

                Button("Start") { controller.beginCountdown(reduceMotion: reduceMotion) }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!controller.canStartCaptureActions)
                    .accessibilityIdentifier("workoutSession.start")
                Button("Skip countdown") { controller.beginAutoRecording() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .disabled(!controller.canStartCaptureActions)
                    .accessibilityIdentifier("workoutSession.skipCountdown")
            }
            .padding(AppSpacing.page)
            .padding(.bottom, AppSpacing.medium)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.55), .black.opacity(0.82)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private var flipCameraButton: some View {
        Button {
            Task { await controller.flipCamera() }
        } label: {
            Image(systemName: "camera.rotate.fill")
                .font(.title3.bold())
                .foregroundStyle(.white)
                .frame(minWidth: 44, minHeight: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel("Flip camera")
        .accessibilityIdentifier("workoutSession.flip")
    }
}

struct WorkoutSessionCountdownOverlay: View {
    let value: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 120
    @ScaledMetric(relativeTo: .largeTitle) private var accessibilityCountdownSize: CGFloat = 72

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            Text(value == 0 ? "START" : "\(value)")
                .font(
                    .system(
                        size: dynamicTypeSize.isAccessibilitySize ? accessibilityCountdownSize : countdownSize,
                        weight: .heavy,
                        design: .rounded
                    )
                )
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .accessibilityIdentifier("workoutSession.countdown")
                .accessibilityLabel("Countdown \(value)")
        }
    }
}
