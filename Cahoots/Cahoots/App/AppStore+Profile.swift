import Foundation

extension AppStore {
    func updateNotificationSettings(_ settings: UserNotificationSettings) async -> Bool {
        let previous = snapshot?.notificationSettings
        snapshot?.notificationSettings = settings
        guard await applyCommand(.updateNotificationSettings(settings)) else {
            snapshot?.notificationSettings = previous
            return false
        }
        await rebuildNotificationPlan()
        return true
    }

    func updateDisplayName(_ name: String) async {
        let clean = TextSanitizer.clean(name, maximumLength: 40)
        guard clean.count >= 2 else { return }
        _ = await applyCommand(.updateProfile(displayName: clean, appearance: nil, showsExactTotals: nil))
    }

    func setAppearance(_ appearance: AppearancePreference) async {
        _ = await applyCommand(.updateProfile(displayName: nil, appearance: appearance, showsExactTotals: nil))
    }

    func setColorTheme(_ theme: AppColorTheme) {
        guard theme != colorTheme else { return }
        colorTheme = theme
        AppColorThemeBridge.current = theme
        UserDefaults.standard.set(theme.rawValue, forKey: AppDefaults.colorTheme)
    }

    func requestNotifications() async {
        if var settings = snapshot?.notificationSettings {
            settings.primerDismissed = true
            _ = await applyCommand(.updateNotificationSettings(settings))
        }
        do {
            let granted = try await environment.notifications.requestAuthorization()
            notificationsDenied = !granted
            notificationAuthorizationState = granted ? .authorized : .denied
            if !granted { errorBanner = String(localized: "Notifications are off. You can enable them later in Settings.") }
        } catch {
            errorBanner = String(localized: "Notification permission could not be requested.")
        }
        showNotificationPrimer = false
        await rebuildNotificationPlan()
    }

    func dismissNotificationPrimer() async {
        if var settings = snapshot?.notificationSettings {
            settings.primerDismissed = true
            _ = await applyCommand(.updateNotificationSettings(settings))
        }
        showNotificationPrimer = false
    }
}
