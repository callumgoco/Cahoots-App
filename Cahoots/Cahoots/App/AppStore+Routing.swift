import Foundation
import OSLog

extension AppStore {
    func handleURL(_ url: URL) {
        guard let route = AppRoute.parse(url) else {
            errorBanner = String(localized: "That Cahoots link is not valid.")
            AppLog.routing.notice("Rejected malformed invitation route")
            return
        }
        applyRoute(route)
    }

    /// Handles local and remote notification taps. Prefers `deepLink`, then kind/group metadata.
    func handleNotificationUserInfo(_ userInfo: [AnyHashable: Any]) {
        if let deepLink = userInfo["deepLink"] as? String, let url = URL(string: deepLink), let route = AppRoute.parse(url) {
            applyRoute(route)
            return
        }
        guard let groupString = userInfo["groupID"] as? String, let groupID = UUID(uuidString: groupString) else {
            AppLog.routing.notice("Notification tap missing usable deep link metadata")
            return
        }
        let kind = (userInfo["kind"] as? String).flatMap(CahootsNotificationKind.init(rawValue:))
        let proposalID = (userInfo["proposalID"] as? String).flatMap(UUID.init(uuidString:))
        switch kind {
        case .vote, .voteOpened:
            applyRoute(.openVote(groupID: groupID, proposalID: proposalID))
        case .daily, .evening, .deadline, .roundStarting, .none:
            applyRoute(.logWorkout(groupID: groupID))
        }
    }

    func clearPendingJoinRoute() { pendingJoinCode = nil }

    func consumePendingWorkoutSession() {
        presentWorkoutSession = false
        pendingLogWorkoutGroupID = nil
        pendingWorkoutSessionRevision += 1
    }

    func consumePresentOpenVote() {
        presentOpenVote = false
    }

    func consumePresentInvite() {
        presentInvite = false
    }

    /// Switches to Crew and opens the invite share screen when possible.
    func presentInviteFlow(groupID: UUID? = nil) {
        if let groupID {
            selectGroup(groupID)
        }
        selectedTab = 1
        presentInvite = true
    }

    /// Switches to Crew and opens the active proposal vote when possible.
    func presentVote(groupID: UUID? = nil, proposalID: UUID? = nil) {
        guard let resolvedGroupID = groupID ?? currentGroup?.id else {
            selectedTab = 1
            return
        }
        applyRoute(.openVote(
            groupID: resolvedGroupID,
            proposalID: proposalID ?? currentProposal?.id
        ))
    }

    func notePendingWorkoutSessionChanged() {
        pendingWorkoutSessionRevision += 1
    }

    func applyRoute(_ route: AppRoute) {
        switch route {
        case .joinGroup(let code):
            pendingJoinCode = code
            pendingLogWorkoutGroupID = nil
            pendingOpenVoteProposalID = nil
            presentWorkoutSession = false
            presentOpenVote = false
            presentInvite = false
        case .logWorkout(let groupID):
            pendingLogWorkoutGroupID = groupID
            pendingOpenVoteProposalID = nil
            presentOpenVote = false
            presentInvite = false
        case .openVote(let groupID, let proposalID):
            pendingOpenVoteProposalID = proposalID
            pendingLogWorkoutGroupID = nil
            presentWorkoutSession = false
            presentInvite = false
            selectGroup(groupID)
            selectedTab = 1
            presentOpenVote = true
        }
        presentPendingRouteIfPossible()
    }

    func presentPendingRouteIfPossible() {
        guard hasCompletedOnboarding, isSignedIn else { return }
        if let groupID = pendingLogWorkoutGroupID {
            selectGroup(groupID)
            selectedTab = 0
            presentWorkoutSession = true
            return
        }
        if presentOpenVote {
            if let proposalID = pendingOpenVoteProposalID,
               let proposal = snapshot?.proposals.first(where: { $0.id == proposalID }) {
                selectGroup(proposal.groupID)
            }
            selectedTab = 1
            return
        }
        guard pendingJoinCode != nil else { return }
        selectedTab = currentGroup == nil ? 0 : 1
    }
}
