import SwiftUI
import UIKit

struct WorkoutSessionPermissionView: View {
    @Bindable var controller: WorkoutSessionController
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: AppSpacing.large) {
            Image(systemName: "camera.fill")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(AppColors.danger)
                .accessibilityHidden(true)
            Text("Camera required")
                .font(.title2.bold())
            Text("Camera access is needed to film a clip for the crew. You can still skip recording and enter today’s amount.")
                .multilineTextAlignment(.center)
                .foregroundStyle(AppColors.secondaryInk)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("workoutSession.openSettings")
            Button("Skip recording") {
                controller.skipRecording()
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(!controller.openedWhileWindowOpen)
            .accessibilityIdentifier("workoutSession.skipRecording")
            Spacer()
        }
        .padding(AppSpacing.page)
        .roundPage()
    }
}
