import Foundation

/// Canonical UserDefaults keys for Cahoots, with one-shot migration from legacy `round.*` keys.
enum AppDefaults {
    // Immutable string keys are nonisolated so background actors (e.g. NotificationService)
    // can read them under SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor.
    nonisolated static let onboardingComplete = "cahoots.onboarding.complete"
    nonisolated static let activeGroupID = "cahoots.activeGroupID"
    nonisolated static let splashPlayed = "cahoots.splash.played"
    nonisolated static let colorTheme = "cahoots.colorTheme"
    nonisolated static let pendingWorkoutPrefix = "cahoots.pendingWorkoutSession."
    nonisolated static let proposalDraftPrefix = "cahoots.proposalDraft."
    nonisolated static let notificationPrefix = "cahoots."
    nonisolated static let memberCountPrefix = "cahoots.memberCount."

    nonisolated static let legacyOnboardingComplete = "round.onboarding.complete"
    nonisolated static let legacyActiveGroupID = "round.activeGroupID"
    nonisolated static let legacyPendingWorkoutPrefix = "round.pendingWorkoutSession."
    nonisolated static let legacyProposalDraftPrefix = "round.proposalDraft."
    nonisolated static let legacyNotificationPrefix = "round."

    /// True when XCTest is driving the process — skip long splash choreography.
    static var isRunningUITests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.arguments.contains("-skipSplash")
    }

    static func migrateLegacyKeysIfNeeded(defaults: UserDefaults = .standard) {
        migrateBool(from: legacyOnboardingComplete, to: onboardingComplete, defaults: defaults)
        migrateString(from: legacyActiveGroupID, to: activeGroupID, defaults: defaults)
        migratePrefixedData(from: legacyPendingWorkoutPrefix, to: pendingWorkoutPrefix, defaults: defaults)
        migratePrefixedData(from: legacyProposalDraftPrefix, to: proposalDraftPrefix, defaults: defaults)
    }

    private static func migrateBool(from oldKey: String, to newKey: String, defaults: UserDefaults) {
        guard defaults.object(forKey: newKey) == nil, defaults.object(forKey: oldKey) != nil else { return }
        defaults.set(defaults.bool(forKey: oldKey), forKey: newKey)
        defaults.removeObject(forKey: oldKey)
    }

    private static func migrateString(from oldKey: String, to newKey: String, defaults: UserDefaults) {
        guard defaults.object(forKey: newKey) == nil, let value = defaults.string(forKey: oldKey) else { return }
        defaults.set(value, forKey: newKey)
        defaults.removeObject(forKey: oldKey)
    }

    private static func migratePrefixedData(from oldPrefix: String, to newPrefix: String, defaults: UserDefaults) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(oldPrefix) {
            let suffix = String(key.dropFirst(oldPrefix.count))
            let newKey = newPrefix + suffix
            if defaults.object(forKey: newKey) == nil, let value = defaults.object(forKey: key) {
                defaults.set(value, forKey: newKey)
            }
            defaults.removeObject(forKey: key)
        }
    }
}
