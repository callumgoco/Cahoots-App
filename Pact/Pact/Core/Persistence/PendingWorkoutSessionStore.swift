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
    private static let prefix = "round.pendingWorkoutSession."

    private static func key(challengeID: UUID, userID: UUID) -> String {
        "\(prefix)\(challengeID.uuidString).\(userID.uuidString)"
    }

    static func load(challengeID: UUID, userID: UUID) -> PendingWorkoutSession? {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: key(challengeID: challengeID, userID: userID)) else { return nil }
        return try? JSONDecoder().decode(PendingWorkoutSession.self, from: data)
    }

    static func save(_ session: PendingWorkoutSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        UserDefaults.standard.set(data, forKey: key(challengeID: session.challengeID, userID: session.userID))
    }

    static func clear(challengeID: UUID, userID: UUID) {
        UserDefaults.standard.removeObject(forKey: key(challengeID: challengeID, userID: userID))
    }
}
