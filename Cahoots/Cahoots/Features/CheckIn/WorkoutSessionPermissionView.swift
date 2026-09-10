import SwiftUI
import UIKit

struct WorkoutSessionPermissionView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: AppSpacing.large) {
            Image(systemName: "camera.fill")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(AppColors.danger)
                .accessibilityHidden(true)
            Text("Camera required")
                .font(.title2.bold())
            Text("A short proof clip is required to unlock the crew feed. Honour-system-only check-ins are not available.")
                .multilineTextAlignment(.center)
                .foregroundStyle(AppColors.secondaryInk)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("workoutSession.openSettings")
            Spacer()
        }
        .padding(AppSpacing.page)
        .roundPage()
    }
}
