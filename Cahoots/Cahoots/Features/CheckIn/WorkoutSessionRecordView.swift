import SwiftUI

struct WorkoutSessionRecordView: View {
    @Bindable var controller: WorkoutSessionController

    var body: some View {
        VStack {
            HStack {
                if controller.isActivelyRecording {
                    Label(controller.formatElapsed(controller.recordingElapsed), systemImage: "record.circle.fill")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.red)
                        .padding(10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(String(localized: "Recording"))
                        .accessibilityValue(controller.formatElapsed(controller.recordingElapsed))
                }
                Spacer()
                flipCameraButton
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
                Button {
                    Task { await controller.stopRecording() }
                } label: {
                    Circle()
                        .fill(.red)
                        .frame(width: 72, height: 72)
                        .overlay(RoundedRectangle(cornerRadius: 8).fill(.white).frame(width: 28, height: 28))
                }
                .frame(minWidth: 72, minHeight: 72)
                .accessibilityLabel("Stop recording")
                .accessibilityIdentifier("workoutSession.stop")
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
