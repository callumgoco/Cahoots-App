import OSLog
import UIKit
import UserNotifications

final class CahootsAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Held until `store` is attached so a cold-start tap is not dropped.
    private var pendingNotificationUserInfo: [AnyHashable: Any]?

    weak var store: AppStore? {
        didSet {
            UNUserNotificationCenter.current().delegate = self
            Task { @MainActor in
                self.flushPendingNotificationTapIfNeeded()
            }
        }
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

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

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        await MainActor.run {
            if let store {
                store.handleNotificationUserInfo(userInfo)
            } else {
                pendingNotificationUserInfo = userInfo
            }
        }
    }

    @MainActor
    private func flushPendingNotificationTapIfNeeded() {
        guard let store, let userInfo = pendingNotificationUserInfo else { return }
        pendingNotificationUserInfo = nil
        store.handleNotificationUserInfo(userInfo)
    }
}
