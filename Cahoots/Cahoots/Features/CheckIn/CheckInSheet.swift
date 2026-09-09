import SwiftUI

/// Legacy entry point retained for any remaining call sites; the live flow is `WorkoutSessionView`.
struct CheckInSheet: View {
    var body: some View {
        WorkoutSessionView()
    }
}
