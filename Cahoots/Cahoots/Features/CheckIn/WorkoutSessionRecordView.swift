import SwiftUI

struct WorkoutSessionRecordView: View {
    @Bindable var controller: WorkoutSessionController

    var body: some View {
        VStack {
            HStack {
                Spacer()
                CircularIconButton(
                    systemName: "camera.rotate.fill",
                    style: .material,
                    accessibilityLabel: String(localized: "Flip camera"),
                    accessibilityIdentifier: "workoutSession.flip"
                ) {
                    Task { await controller.flipCamera() }
                }
                .disabled(controller.isActivelyRecording)
                .opacity(controller.isActivelyRecording ? 0.4 : 1)
            }
            .padding(AppSpacing.page)

            Spacer()

            Text(controller.isActivelyRecording ? controller.recordHint : String(localized: "Tap to record"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.bottom, 8)

            if controller.isActivelyRecording {
                HStack(alignment: .center, spacing: AppSpacing.medium) {
                    Label(controller.formatElapsed(controller.recordingElapsed), systemImage: "record.circle.fill")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: Capsule())
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(String(localized: "Recording"))
                        .accessibilityValue(controller.formatElapsed(controller.recordingElapsed))

                    Button {
                        Task { await controller.stopRecording() }
                    } label: {
                        Circle()
                            .fill(.red)
                            .frame(width: 64, height: 64)
                            .overlay(RoundedRectangle(cornerRadius: 8).fill(.white).frame(width: 24, height: 24))
                            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                    }
                    .frame(minWidth: 64, minHeight: 64)
                    .accessibilityLabel("Stop recording")
                    .accessibilityIdentifier("workoutSession.stop")
                }
                .padding(.bottom, 40)
            } else {
                // Idle record control is for retakes; Start / countdown auto-begin capture.
                Button {
                    Task { await controller.startRecording() }
                } label: {
                    Circle()
                        .strokeBorder(.white, lineWidth: 6)
                        .frame(width: 78, height: 78)
                        .overlay(
                            Circle()
                                .fill(.red)
                                .frame(width: 62, height: 62)
                        )
                }
                .frame(minWidth: 78, minHeight: 78)
                .accessibilityLabel("Start recording")
                .accessibilityIdentifier("workoutSession.record")
                .disabled(!controller.isCaptureReady)
                .padding(.bottom, 40)
            }
        }
    }
}
