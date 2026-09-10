import Foundation

enum AppRoute: Equatable, Sendable {
    case joinGroup(code: String)
    case logWorkout(groupID: UUID)
    case openVote(groupID: UUID, proposalID: UUID?)

    static func parse(_ url: URL, inviteHost: String = AppIdentity.inviteHost) -> AppRoute? {
        if url.scheme?.lowercased() == "cahoots" {
            return parseCustomScheme(url)
        }
        if url.scheme?.lowercased() == "https", url.host?.lowercased() == inviteHost.lowercased() {
            return parseHTTPSPath(url.pathComponents.filter { $0 != "/" })
        }
        return nil
    }

    /// Builds a deep link suitable for local/remote notification payloads.
    static func deepLink(for item: NotificationPlanItem) -> String {
        switch item.kind {
        case .vote, .voteOpened:
            if let proposalID = item.proposalID {
                return "cahoots://vote/\(item.groupID.uuidString)/\(proposalID.uuidString)"
            }
            return "cahoots://vote/\(item.groupID.uuidString)"
        case .daily, .evening, .deadline, .roundStarting:
            return "cahoots://log/\(item.groupID.uuidString)"
        }
    }

    private static func parseCustomScheme(_ url: URL) -> AppRoute? {
        let host = url.host?.lowercased()
        let pathParts = url.pathComponents.filter { $0 != "/" }

        if host == "log", let groupID = pathParts.first.flatMap(UUID.init(uuidString:)) {
            return .logWorkout(groupID: groupID)
        }
        if host == "vote", let groupID = pathParts.first.flatMap(UUID.init(uuidString:)) {
            let proposalID = pathParts.dropFirst().first.flatMap(UUID.init(uuidString:))
            return .openVote(groupID: groupID, proposalID: proposalID)
        }

        let parts = [url.host].compactMap { $0 } + pathParts
        guard parts.first?.lowercased() == "join" else { return nil }
        guard let normalized = parts.dropFirst().first.map(normalizeCode), normalized.count == 6 else { return nil }
        return .joinGroup(code: normalized)
    }

    private static func parseHTTPSPath(_ parts: [String]) -> AppRoute? {
        guard let first = parts.first?.lowercased() else { return nil }
        switch first {
        case "log":
            guard let groupID = parts.dropFirst().first.flatMap(UUID.init(uuidString:)) else { return nil }
            return .logWorkout(groupID: groupID)
        case "vote":
            guard let groupID = parts.dropFirst().first.flatMap(UUID.init(uuidString:)) else { return nil }
            let proposalID = parts.dropFirst(2).first.flatMap(UUID.init(uuidString:))
            return .openVote(groupID: groupID, proposalID: proposalID)
        case "join":
            guard let normalized = parts.dropFirst().first.map(normalizeCode), normalized.count == 6 else { return nil }
            return .joinGroup(code: normalized)
        default:
            return nil
        }
    }

    nonisolated private static func normalizeCode(_ value: String) -> String {
        String(value.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
    }
}
