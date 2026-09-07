import Foundation

struct ProposalDraftStore: Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(userID: UUID, groupID: UUID) -> ProposalDraft? {
        guard let data = defaults.data(forKey: key(userID: userID, groupID: groupID)) else { return nil }
        return try? JSONDecoder().decode(ProposalDraft.self, from: data)
    }

    func save(_ draft: ProposalDraft, userID: UUID, groupID: UUID) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        defaults.set(data, forKey: key(userID: userID, groupID: groupID))
    }

    func clear(userID: UUID, groupID: UUID) {
        defaults.removeObject(forKey: key(userID: userID, groupID: groupID))
    }

    private func key(userID: UUID, groupID: UUID) -> String {
        "round.proposalDraft.\(userID.uuidString).\(groupID.uuidString)"
    }
}
