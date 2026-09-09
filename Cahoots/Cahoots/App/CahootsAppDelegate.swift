import OSLog
import UIKit

final class CahootsAppDelegate: NSObject, UIApplicationDelegate {
    weak var store: AppStore?

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        guard let store else { return }
        Task { @MainActor in
            await store.handleDevicePushToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        AppLog.notifications.error("Remote notification registration failed: \(error.localizedDescription, privacy: .private)")
    }
}
