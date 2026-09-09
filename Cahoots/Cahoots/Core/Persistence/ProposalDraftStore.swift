import Foundation

struct ProposalDraftStore: Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(userID: UUID, groupID: UUID) -> ProposalDraft? {
        AppDefaults.migrateLegacyKeysIfNeeded(defaults: defaults)
        if let data = defaults.data(forKey: key(userID: userID, groupID: groupID)) {
            return try? JSONDecoder().decode(ProposalDraft.self, from: data)
        }
        let legacy = legacyKey(userID: userID, groupID: groupID)
        guard let data = defaults.data(forKey: legacy) else { return nil }
        defaults.set(data, forKey: key(userID: userID, groupID: groupID))
        defaults.removeObject(forKey: legacy)
        return try? JSONDecoder().decode(ProposalDraft.self, from: data)
    }

    func save(_ draft: ProposalDraft, userID: UUID, groupID: UUID) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        defaults.set(data, forKey: key(userID: userID, groupID: groupID))
        defaults.removeObject(forKey: legacyKey(userID: userID, groupID: groupID))
    }

    func clear(userID: UUID, groupID: UUID) {
        defaults.removeObject(forKey: key(userID: userID, groupID: groupID))
        defaults.removeObject(forKey: legacyKey(userID: userID, groupID: groupID))
    }

    private func key(userID: UUID, groupID: UUID) -> String {
        "\(AppDefaults.proposalDraftPrefix)\(userID.uuidString).\(groupID.uuidString)"
    }

    private func legacyKey(userID: UUID, groupID: UUID) -> String {
        "\(AppDefaults.legacyProposalDraftPrefix)\(userID.uuidString).\(groupID.uuidString)"
    }
}
