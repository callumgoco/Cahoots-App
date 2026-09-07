import Foundation

enum FriendPostedCopy {
    /// Lock-screen / push body. Never includes quantity, points, or media hints.
    static func lockScreenBody(actorName: String, groupName: String, viewerHasCompleted: Bool) -> String {
        if viewerHasCompleted {
            return String(localized: "\(actorName) just posted in \(groupName).")
        }
        return String(localized: "\(actorName) posted in \(groupName) — log yours to see it.")
    }

    static func lockScreenTitle(groupName: String) -> String {
        String(localized: "\(groupName)")
    }
}
