import Foundation

/// Canonical UserDefaults keys for Cahoots, with one-shot migration from legacy `round.*` keys.
enum AppDefaults {
    static let onboardingComplete = "cahoots.onboarding.complete"
    static let activeGroupID = "cahoots.activeGroupID"
    static let pendingWorkoutPrefix = "cahoots.pendingWorkoutSession."
    static let proposalDraftPrefix = "cahoots.proposalDraft."
    static let notificationPrefix = "cahoots."

    static let legacyOnboardingComplete = "round.onboarding.complete"
    static let legacyActiveGroupID = "round.activeGroupID"
    static let legacyPendingWorkoutPrefix = "round.pendingWorkoutSession."
    static let legacyProposalDraftPrefix = "round.proposalDraft."
    static let legacyNotificationPrefix = "round."

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
