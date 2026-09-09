import Foundation

/// Persists an in-progress cardio check-in (start clip recorded, finish clip still needed).
struct PendingWorkoutSession: Codable, Hashable, Sendable {
    var challengeID: UUID
    var userID: UUID
    var requirementDate: Date
    var startClip: WorkoutClip
    var updatedAt: Date
}

enum PendingWorkoutSessionStore {
    private static let prefix = AppDefaults.pendingWorkoutPrefix
    private static let legacyPrefix = AppDefaults.legacyPendingWorkoutPrefix

    private static func key(challengeID: UUID, userID: UUID) -> String {
        "\(prefix)\(challengeID.uuidString).\(userID.uuidString)"
    }

    private static func legacyKey(challengeID: UUID, userID: UUID) -> String {
        "\(legacyPrefix)\(challengeID.uuidString).\(userID.uuidString)"
    }

    static func load(challengeID: UUID, userID: UUID) -> PendingWorkoutSession? {
        AppDefaults.migrateLegacyKeysIfNeeded()
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: key(challengeID: challengeID, userID: userID)) {
            return try? JSONDecoder().decode(PendingWorkoutSession.self, from: data)
        }
        if let data = defaults.data(forKey: legacyKey(challengeID: challengeID, userID: userID)) {
            defaults.set(data, forKey: key(challengeID: challengeID, userID: userID))
            defaults.removeObject(forKey: legacyKey(challengeID: challengeID, userID: userID))
            return try? JSONDecoder().decode(PendingWorkoutSession.self, from: data)
        }
        return nil
    }

    static func save(_ session: PendingWorkoutSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        UserDefaults.standard.set(data, forKey: key(challengeID: session.challengeID, userID: session.userID))
        UserDefaults.standard.removeObject(forKey: legacyKey(challengeID: session.challengeID, userID: session.userID))
    }

    static func clear(challengeID: UUID, userID: UUID) {
        UserDefaults.standard.removeObject(forKey: key(challengeID: challengeID, userID: userID))
        UserDefaults.standard.removeObject(forKey: legacyKey(challengeID: challengeID, userID: userID))
    }

    static func clear() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) || key.hasPrefix(legacyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
