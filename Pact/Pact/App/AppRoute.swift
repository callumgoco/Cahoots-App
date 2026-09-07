import Foundation

enum AppRoute: Equatable, Sendable {
    case joinGroup(code: String)
    case logWorkout(groupID: UUID)

    static func parse(_ url: URL, inviteHost: String = AppIdentity.inviteHost) -> AppRoute? {
        let code: String?
        if url.scheme?.lowercased() == "round" {
            if url.host?.lowercased() == "log",
               let groupString = url.pathComponents.filter({ $0 != "/" }).first,
               let groupID = UUID(uuidString: groupString) {
                return .logWorkout(groupID: groupID)
            }
            let parts = [url.host].compactMap { $0 } + url.pathComponents.filter { $0 != "/" }
            guard parts.first?.lowercased() == "join" else { return nil }
            code = parts.dropFirst().first
        } else if url.scheme?.lowercased() == "https", url.host?.lowercased() == inviteHost.lowercased() {
            let parts = url.pathComponents.filter { $0 != "/" }
            if parts.first?.lowercased() == "log",
               let groupString = parts.dropFirst().first,
               let groupID = UUID(uuidString: groupString) {
                return .logWorkout(groupID: groupID)
            }
            guard parts.first?.lowercased() == "join" else { return nil }
            code = parts.dropFirst().first
        } else {
            return nil
        }
        guard let normalized = code.map(normalizeCode), normalized.count == 6 else { return nil }
        return .joinGroup(code: normalized)
    }

    nonisolated private static func normalizeCode(_ value: String) -> String {
        String(value.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
    }
}
