import Foundation
import OSLog

extension AppStore {
    var activeMembershipCount: Int {
        activeGroups.count
    }

    var effectiveEntitlement: Entitlement {
        if let user = snapshot?.currentUser {
            let fromProfile = user.effectiveEntitlement(at: environment.clock.now)
            if fromProfile.hasPlusAccess { return fromProfile }
        }
        return cachedEntitlement
    }

    var crewMembershipLimit: Int {
        effectiveEntitlement.membershipLimit
    }

    var canAddCrewMembership: Bool {
        activeMembershipCount < crewMembershipLimit
    }

    func presentPaywall(_ context: PaywallContext) {
        paywallContext = context
    }

    func dismissPaywall() {
        paywallContext = nil
    }

    func refreshEntitlements() async {
        cachedEntitlement = await environment.entitlements.currentEntitlement()
        if let user = snapshot?.currentUser {
            let profile = user.effectiveEntitlement(at: environment.clock.now)
            if profile.hasPlusAccess {
                cachedEntitlement = profile
            }
        }
        await syncEntitlementToServerIfNeeded()
    }

    func purchasePlus(_ productID: PlusProductID) async -> String? {
        do {
            try await environment.entitlements.purchase(productID)
            await refreshEntitlements()
            await syncEntitlementToServerIfNeeded()
            noticeBanner = String(localized: "You’re on Cahoots Plus.")
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func restorePlusPurchases() async -> String? {
        do {
            try await environment.entitlements.restore()
            await refreshEntitlements()
            await syncEntitlementToServerIfNeeded()
            if effectiveEntitlement.hasPlusAccess {
                noticeBanner = String(localized: "Plus restored.")
                return nil
            }
            return String(localized: "No Plus subscription found for this Apple ID.")
        } catch {
            return error.localizedDescription
        }
    }

    /// Leave the current crew, then create or join so Free users can switch without Plus.
    func leaveCurrentCrewAndContinue(context: PaywallContext) async -> String? {
        guard currentGroup != nil else {
            return String(localized: "You’re not in a crew to leave.")
        }
        let left = await leaveCurrentGroup()
        guard left else {
            return errorBanner ?? String(localized: "Couldn’t leave your current crew.")
        }
        dismissPaywall()
        switch context {
        case .create:
            // Caller presents CreateGroupView after dismiss.
            pendingPaywallContinue = .create
            return nil
        case .join(let code):
            if let message = await joinGroup(code: code) {
                return message
            }
            return nil
        case .manage:
            return nil
        }
    }

    private func syncEntitlementToServerIfNeeded() async {
        guard environment.repository.mode == .live else { return }
        guard let jws = await environment.entitlements.latestSignedTransactionJWS() else { return }
        do {
            let entitlement = try await environment.repository.syncEntitlement(signedTransaction: jws)
            cachedEntitlement = entitlement
            if var snapshot, var user = Optional(snapshot.currentUser) {
                user.entitlement = entitlement
                snapshot.currentUser = user
                if let index = snapshot.users.firstIndex(where: { $0.id == user.id }) {
                    snapshot.users[index] = user
                }
                self.snapshot = snapshot
            }
        } catch {
            AppLog.lifecycle.error("Entitlement sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

enum PendingPaywallContinue: Equatable, Sendable {
    case create
}
